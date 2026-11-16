// Deepgram streaming probe for the transcript stall detector (3.10.0 plan, TG1).
// Streams local 16 kHz mono PCM files to Deepgram in real time with the app's own
// listen settings (DeepgramService.makeListenQueryItems) and reports message cadence,
// speech-event timing, and the words a forced reconnect costs. See README.md.
// Usage: DEEPGRAM_API_KEY=... node dg-probe.mjs <audioDir> cadence|onset|reconnect
// The key is read from the environment and never printed. Needs Node 22+ (built-in WebSocket).
import fs from 'node:fs'
import path from 'node:path'

const [dir, test] = process.argv.slice(2)
const KEY = process.env.DEEPGRAM_API_KEY
if (!KEY) { console.error('no key'); process.exit(1) }
const RATE = 16000, BYTES_PER_SEC = RATE * 2, CHUNK_MS = 100, CHUNK = BYTES_PER_SEC * CHUNK_MS / 1000
const URL_ = 'wss://api.deepgram.com/v1/listen?model=nova-3&language=en&smart_format=true&filler_words=true&diarize_model=latest&interim_results=true&utterance_end_ms=1000&vad_events=true&endpointing=300&encoding=linear16&sample_rate=16000&channels=1'
const load = (name) => fs.readFileSync(path.join(dir, name))
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const now = () => performance.now() / 1000

function open() {
  return new Promise((resolve, reject) => {
    const t0 = now()
    const ws = new WebSocket(URL_, ['token', KEY])
    const msgs = []
    ws.onmessage = (ev) => { try { msgs.push({ t: now(), m: JSON.parse(ev.data) }) } catch {} }
    ws.onopen = () => resolve({ ws, msgs, handshake: now() - t0 })
    ws.onerror = (e) => reject(new Error('ws error ' + (e.message || '')))
  })
}

// Stream `pcm` in real time. hooks.onTick(tSec) may return a replacement connection.
async function stream(conn, pcm, { keepAlive = true } = {}) {
  const start = now(); let sent = 0, lastKA = start
  while (sent < pcm.length) {
    const due = start + (sent / BYTES_PER_SEC)
    const wait = due - now(); if (wait > 0) await sleep(wait * 1000)
    conn.ws.send(pcm.subarray(sent, Math.min(pcm.length, sent + CHUNK))); sent += CHUNK
    if (keepAlive && now() - lastKA >= 5) { conn.ws.send(JSON.stringify({ type: 'KeepAlive' })); lastKA = now() }
  }
  return start
}
const kind = (m) => m.type === 'Results' ? ((m.channel?.alternatives?.[0]?.transcript || '').trim() ? (m.is_final ? 'final' : 'interim') : (m.is_final ? 'empty_final' : 'empty_interim')) : m.type

async function cadence(name) {
  const pcm = load(name).subarray(0, BYTES_PER_SEC * 60)
  const conn = await open(); const start = await stream(conn, pcm); await sleep(1500); conn.ws.close()
  const counts = {}; const times = []
  for (const { t, m } of conn.msgs) { const k = kind(m); counts[k] = (counts[k] || 0) + 1; times.push(t - start) }
  let maxGap = 0, prev = 0; for (const t of times) { maxGap = Math.max(maxGap, t - prev); prev = t }
  maxGap = Math.max(maxGap, 60 - prev)
  const words = conn.msgs.filter(x => kind(x.m) === 'final').map(x => x.m.channel.alternatives[0].transcript).join(' | ')
  console.log(JSON.stringify({ test: 'cadence', audio: name, handshake_s: +conn.handshake.toFixed(2), messages: times.length, counts, first_message_s: times.length ? +times[0].toFixed(2) : null, max_gap_between_messages_s: +maxGap.toFixed(2), final_text_chars: words.length }))
}

async function onset(leadName, leadSec, speechOffsetSec) {
  const lead = load(leadName).subarray(0, BYTES_PER_SEC * leadSec)
  const sp = load('speech.raw').subarray(BYTES_PER_SEC * speechOffsetSec, BYTES_PER_SEC * (speechOffsetSec + 8))
  const conn = await open(); const start = await stream(conn, Buffer.concat([lead, sp])); await sleep(1500); conn.ws.close()
  const rel = (t) => +(t - start - leadSec).toFixed(2)
  const firstText = conn.msgs.find(x => ['interim', 'final'].includes(kind(x.m)))
  const firstSpeech = conn.msgs.find(x => x.m.type === 'SpeechStarted' && x.t - start >= leadSec - 0.5)
  const speechDuringLead = conn.msgs.filter(x => x.m.type === 'SpeechStarted' && x.t - start < leadSec - 0.5).length
  console.log(JSON.stringify({ test: 'onset', lead: leadName, speech_offset: speechOffsetSec, first_text_after_onset_s: firstText ? rel(firstText.t) : null, first_text_audio_start_s: firstText ? +(firstText.m.start - leadSec).toFixed(2) : null, speech_started_after_onset_s: firstSpeech ? rel(firstSpeech.t) : null, speech_started_during_lead: speechDuringLead }))
}

const norm = (w) => w.toLowerCase().replace(/[^a-z0-9']/g, '')
function finalsWords(msgs, offset = 0) {
  const out = []
  for (const { m } of msgs) if (m.type === 'Results' && m.is_final) for (const w of (m.channel?.alternatives?.[0]?.words || [])) out.push({ w: norm(w.word), s: w.start + offset })
  return out
}
async function reference(seconds) {
  const pcm = load('speech.raw').subarray(0, BYTES_PER_SEC * seconds)
  const conn = await open(); await stream(conn, pcm); conn.ws.send(JSON.stringify({ type: 'CloseStream' })); await sleep(2500); conn.ws.close()
  return finalsWords(conn.msgs)
}
// The app's forced reconnect: detection at R, keep sending 1 s, drop the socket without
// finishing, open a new one while audio keeps flowing (and is dropped), then continue.
async function reconnectRun(seconds, R, ref) {
  const pcm = load('speech.raw').subarray(0, BYTES_PER_SEC * seconds)
  let conn = await open(); const start = now(); let sent = 0, lastKA = start
  let oldMsgs = null, lastInterim = null, newOffset = null, handshake = null, droppedSec = 0, reconnecting = null, closedAt = null
  while (sent < pcm.length) {
    const audioT = sent / BYTES_PER_SEC
    const wait = start + audioT - now(); if (wait > 0) await sleep(wait * 1000)
    if (oldMsgs === null && audioT >= R + 1.0) {
      // Drop the old socket now; anything it has not delivered yet is discarded.
      oldMsgs = conn.msgs.slice(); closedAt = audioT
      const li = [...oldMsgs].reverse().find(x => x.m.type === 'Results'); lastInterim = li && !li.m.is_final ? li.m : null
      conn.ws.onmessage = null; conn.ws.close()
      reconnecting = open().then(c => { conn = c; handshake = c.handshake; newOffset = (now() - start); reconnecting = null })
    }
    if (reconnecting) { droppedSec += CHUNK_MS / 1000 } else {
      if (newOffset !== null && conn.firstAudio === undefined) conn.firstAudio = audioT
      conn.ws.send(pcm.subarray(sent, Math.min(pcm.length, sent + CHUNK)))
      if (now() - lastKA >= 5) { conn.ws.send(JSON.stringify({ type: 'KeepAlive' })); lastKA = now() }
    }
    sent += CHUNK
  }
  conn.ws.send(JSON.stringify({ type: 'CloseStream' })); await sleep(2500); conn.ws.close()
  const got = [...finalsWords(oldMsgs), ...finalsWords(conn.msgs, conn.firstAudio)]
  const interimWords = lastInterim ? (lastInterim.channel.alternatives[0].words || []).map(w => ({ w: norm(w.word), s: w.start })) : []
  const window = ref.filter(r => r.s >= R - 8 && r.s <= R + 12)
  const has = (pool, r) => pool.some(g => g.w === r.w && Math.abs(g.s - r.s) <= 1.0)
  const missing = window.filter(r => !has(got, r))
  const missingEvenWithInterim = missing.filter(r => !has(interimWords, r))
  const outside = ref.filter(r => (r.s < R - 8 || r.s > R + 12)); const outsideMissing = outside.filter(r => !has(got, r)).length
  console.log(JSON.stringify({ test: 'reconnect', detect_at_s: R, socket_dropped_at_s: +closedAt.toFixed(1), handshake_s: +handshake.toFixed(2), audio_not_sent_s: +droppedSec.toFixed(1), words_in_window: window.length, words_missing: missing.length, missing_span_s: missing.length ? [+missing[0].s.toFixed(1), +missing[missing.length - 1].s.toFixed(1)] : null, words_missing_if_last_interim_kept: missingEvenWithInterim.length, baseline_mismatch_outside_window: outsideMissing + '/' + outside.length }))
}

if (test === 'cadence') { for (const a of ['silence.raw', 'noise.raw', 'tones.raw', 'speech.raw']) await cadence(a) }
else if (test === 'onset') { for (const [l, o] of [['silence.raw', 5], ['silence.raw', 30], ['silence.raw', 62], ['noise.raw', 5], ['noise.raw', 30], ['noise.raw', 62], ['noise.raw', 95]]) await onset(l, 10, o) }
else if (test === 'reconnect') {
  const ref = await reference(70); console.log(JSON.stringify({ test: 'reference', words: ref.length, seconds: 70 }))
  const ref2 = await reference(70); const same = ref.filter(r => ref2.some(g => g.w === r.w && Math.abs(g.s - r.s) <= 1.0)).length
  console.log(JSON.stringify({ test: 'reference_repeat', words: ref2.length, agree_with_first: same + '/' + ref.length }))
  for (const R of [15, 25, 35, 45, 55]) await reconnectRun(70, R, ref)
}
process.exit(0)
