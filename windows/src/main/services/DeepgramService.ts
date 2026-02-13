import WebSocket from 'ws'
import { EventEmitter } from 'events'

// --- Types ---

export interface TranscriptWord {
  text: string
  start: number
  end: number
  confidence: number
  speaker: number
}

export interface SpeakerSegment {
  id: string
  speaker: number
  text: string
  startTime: number
  endTime: number
  isFinal: boolean
  confidence: number
}

export interface TranscriptUpdate {
  text: string
  speaker: number
  isFinal: boolean
  confidence: number
  words: TranscriptWord[]
  segments: SpeakerSegment[]
}

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error'

export type DeepgramModel = 'nova-2' | 'nova-3'

// --- Deepgram Response Types ---

interface DeepgramResponse {
  type?: string
  channel?: {
    alternatives: Array<{
      transcript: string
      confidence: number
      words: Array<{
        word: string
        punctuated_word?: string
        start: number
        end: number
        confidence: number
        speaker?: number
        speaker_confidence?: number
      }>
    }>
  }
  is_final?: boolean
  speech_final?: boolean
  start?: number
  duration?: number
}

// --- Service ---

export class DeepgramService extends EventEmitter {
  private ws: WebSocket | null = null
  private apiKey = ''
  private _isConnected = false
  private speakerHistory: Map<number, { wordCount: number; totalDuration: number }> = new Map()

  /** Reserved speaker ID for local microphone ("You") */
  static readonly MIC_SPEAKER_ID = 1000

  get isConnected(): boolean {
    return this._isConnected
  }

  configure(apiKey: string): void {
    this.apiKey = apiKey
  }

  connect(model: DeepgramModel = 'nova-3'): void {
    if (!this.apiKey) {
      this.emit('error', new Error('Deepgram API key is required'))
      return
    }

    this.emit('connectionState', 'connecting' as ConnectionState)
    this.speakerHistory.clear()

    const params = new URLSearchParams({
      model,
      language: 'en',
      smart_format: 'true',
      punctuate: 'true',
      diarize: 'true',
      interim_results: 'true',
      utterance_end_ms: model === 'nova-3' ? '1000' : '1500',
      vad_events: 'true',
      endpointing: model === 'nova-3' ? '300' : '500',
      encoding: 'linear16',
      sample_rate: '16000',
      channels: '1'
    })

    const url = `wss://api.deepgram.com/v1/listen?${params}`
    console.log(`[Deepgram] Connecting with model: ${model}`)

    this.ws = new WebSocket(url, {
      headers: { Authorization: `Token ${this.apiKey}` }
    })

    this.ws.on('open', () => {
      this._isConnected = true
      this.emit('connectionState', 'connected' as ConnectionState)
      console.log('[Deepgram] Connected')
    })

    this.ws.on('message', (data: WebSocket.Data) => {
      try {
        const text = data.toString()
        this.parseResponse(text)
      } catch (err) {
        console.error('[Deepgram] Message parse error:', err)
      }
    })

    this.ws.on('close', () => {
      if (this._isConnected) {
        this._isConnected = false
        this.emit('connectionState', 'disconnected' as ConnectionState)
      }
    })

    this.ws.on('error', (err) => {
      if (this._isConnected) {
        console.error('[Deepgram] WebSocket error:', err)
        this.emit('error', err)
        this.emit('connectionState', 'error' as ConnectionState)
      }
    })
  }

  disconnect(): void {
    this._isConnected = false
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
    this.emit('connectionState', 'disconnected' as ConnectionState)
  }

  sendAudio(buffer: ArrayBuffer): void {
    if (!this._isConnected || !this.ws || this.ws.readyState !== WebSocket.OPEN) return
    this.ws.send(Buffer.from(buffer))
  }

  private parseResponse(json: string): void {
    let response: DeepgramResponse
    try {
      response = JSON.parse(json)
    } catch {
      return
    }

    if (!response.channel?.alternatives?.[0]) return

    const alt = response.channel.alternatives[0]
    const isFinal = response.is_final ?? false

    const words: TranscriptWord[] = (alt.words || []).map((w) => ({
      text: w.punctuated_word ?? w.word,
      start: w.start,
      end: w.end,
      confidence: w.confidence,
      speaker: w.speaker ?? 0
    }))

    // Update speaker history for final results
    if (isFinal) {
      for (const w of alt.words || []) {
        const speaker = w.speaker ?? 0
        const info = this.speakerHistory.get(speaker) || { wordCount: 0, totalDuration: 0 }
        info.wordCount += 1
        info.totalDuration += w.end - w.start
        this.speakerHistory.set(speaker, info)
      }
    }

    // Segment by speaker
    const segments = this.segmentBySpeaker(words, isFinal, alt.confidence)

    // Find dominant speaker
    const speakerCounts = new Map<number, number>()
    for (const w of words) {
      speakerCounts.set(w.speaker, (speakerCounts.get(w.speaker) || 0) + 1)
    }
    let dominantSpeaker = 0
    let maxCount = 0
    for (const [speaker, count] of speakerCounts) {
      if (count > maxCount) {
        dominantSpeaker = speaker
        maxCount = count
      }
    }

    const update: TranscriptUpdate = {
      text: alt.transcript,
      speaker: dominantSpeaker,
      isFinal,
      confidence: alt.confidence,
      words,
      segments
    }

    this.emit('transcript', update)
  }

  /**
   * Groups consecutive words by speaker with lookahead to avoid
   * spurious single-word speaker changes.
   */
  private segmentBySpeaker(
    words: TranscriptWord[],
    isFinal: boolean,
    confidence: number
  ): SpeakerSegment[] {
    if (words.length === 0) return []

    const MIN_WORDS_FOR_CHANGE = 2
    const segments: SpeakerSegment[] = []
    let currentSpeaker = words[0].speaker
    let currentWords: TranscriptWord[] = []
    let startTime = words[0].start

    let i = 0
    while (i < words.length) {
      const word = words[i]

      if (word.speaker !== currentSpeaker) {
        // Look ahead to confirm speaker change
        let newSpeakerCount = 0
        let lookAhead = i
        const newSpeaker = word.speaker
        while (lookAhead < words.length && words[lookAhead].speaker === newSpeaker) {
          newSpeakerCount++
          lookAhead++
        }

        if (newSpeakerCount >= MIN_WORDS_FOR_CHANGE) {
          // Confirmed change — save current segment
          if (currentWords.length > 0) {
            segments.push({
              id: crypto.randomUUID(),
              speaker: currentSpeaker,
              text: currentWords.map((w) => w.text).join(' '),
              startTime,
              endTime: currentWords[currentWords.length - 1].end,
              isFinal,
              confidence
            })
          }
          currentSpeaker = newSpeaker
          currentWords = [word]
          startTime = word.start
        } else {
          // Spurious — keep with current speaker
          currentWords.push(word)
        }
      } else {
        currentWords.push(word)
      }
      i++
    }

    // Last segment
    if (currentWords.length > 0) {
      segments.push({
        id: crypto.randomUUID(),
        speaker: currentSpeaker,
        text: currentWords.map((w) => w.text).join(' '),
        startTime,
        endTime: currentWords[currentWords.length - 1].end,
        isFinal,
        confidence
      })
    }

    return segments
  }

  get detectedSpeakerCount(): number {
    return this.speakerHistory.size
  }
}
