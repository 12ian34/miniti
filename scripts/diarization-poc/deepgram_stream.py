#!/usr/bin/env python
"""Mimic the app's Deepgram path: stream linear16 16 kHz audio over the WebSocket with the same
query parameters as DeepgramService.swift (nova-3, diarize_model=latest, smart_format, filler_words,
interim_results, utterance_end_ms=1000, vad_events, endpointing=300) at realtime, collect final
words with speaker labels, and save JSON in the prerecorded response shape for score.py."""
import asyncio, json, os, sys, time, wave
import websockets

KEY = next(l.split('=', 1)[1].strip().strip('"') for l in open('../../../miniti-api/.env') if l.startswith('DEEPGRAM_API_KEY='))
Q = 'model=nova-3&language=en&smart_format=true&filler_words=true&diarize_model=latest&interim_results=true&utterance_end_ms=1000&vad_events=true&endpointing=300&encoding=linear16&sample_rate=16000&channels=1'
Q = os.environ.get('DG_QUERY', Q)  # override for billing experiments
PACE = float(os.environ.get('PACE', '1'))  # x realtime; 2x tripped keepalive ping timeouts on all four streams

async def run(path):
    tag = os.path.basename(path).replace('.16k.wav', '')
    out = os.environ.get('DG_OUT', f'out/deepgram-streaming-{tag}.json')
    if os.path.exists(out): print(tag, 'exists'); return
    with wave.open(path) as w:
        pcm = w.readframes(w.getnframes()); dur = w.getnframes() / w.getframerate()
    words = []
    t0 = time.time()
    async with websockets.connect(f'wss://api.deepgram.com/v1/listen?{Q}', additional_headers={'Authorization': f'Token {KEY}'}, max_size=None, ping_interval=None) as ws:
        async def reader():
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'Results' and d.get('is_final'):
                    alt = d['channel']['alternatives'][0]
                    words.extend(alt.get('words', []))
        rt = asyncio.create_task(reader())
        chunk = 3200  # 100 ms
        for i in range(0, len(pcm), chunk):
            await ws.send(pcm[i:i + chunk]); await asyncio.sleep(0.1 / PACE)
        await ws.send(json.dumps({'type': 'CloseStream'}))
        try: await asyncio.wait_for(rt, timeout=60)
        except asyncio.TimeoutError: pass
    json.dump({'metadata': {'duration': dur, 'wall_s': time.time() - t0, 'pace': PACE}, 'results': {'channels': [{'alternatives': [{'words': words}]}]}}, open(out, 'w'))
    print(tag, 'words', len(words), 'speakers', sorted({w.get('speaker') for w in words}), 'wall %.0fs' % (time.time() - t0), flush=True)

async def main():
    await asyncio.gather(*(run(p) for p in sys.argv[1:]))
asyncio.run(main())
