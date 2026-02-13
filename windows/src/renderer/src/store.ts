import { create } from 'zustand'
import type {
  AppMode,
  AppView,
  InsightsMode,
  DeepgramModel,
  OpenAIModel,
  LiveSegment,
  TranscriptUpdate,
  UsageInfo,
  ConnectionState,
  Meeting
} from './types'
import { MIC_SPEAKER_ID } from './types'

// --- Audio capture state (renderer-side) ---

let micAudioContext: AudioContext | null = null
let micSource: MediaStreamAudioSourceNode | null = null
let micProcessor: ScriptProcessorNode | null = null
let micStream: MediaStream | null = null

let sysAudioContext: AudioContext | null = null
let sysSource: MediaStreamAudioSourceNode | null = null
let sysProcessor: ScriptProcessorNode | null = null
let sysStream: MediaStream | null = null

// --- Store ---

interface AppStore {
  // Navigation
  view: AppView
  setView: (view: AppView) => void

  // App mode
  appMode: AppMode
  hasCompletedOnboarding: boolean
  setAppMode: (mode: AppMode) => void
  completeOnboarding: (mode: AppMode) => void

  // Recording
  isRecording: boolean
  recordingDuration: number
  hasUnsavedSession: boolean
  connectionState: ConnectionState
  currentMeetingId: string | null
  currentMeetingTitle: string

  // Transcript
  liveSegments: LiveSegment[]
  interimText: string
  currentSpeaker: number
  interimSpeaker: number | null
  detectedSpeakers: Set<number>

  // Audio levels
  microphoneLevel: number
  systemAudioLevel: number
  isMonitoring: boolean

  // Insights
  insightsMode: InsightsMode
  isGeneratingInsights: boolean
  liveSummary: string
  liveActionItems: string[]
  liveTopics: string[]
  liveDiscussionFlow: string[]
  liveNotes: string
  // MEDDPICC
  liveMetrics?: string
  liveEconomicBuyer?: string
  liveDecisionCriteria?: string
  liveDecisionProcess?: string
  livePaperProcess?: string
  liveIdentifiedPain?: string
  liveChampion?: string
  liveCompetition?: string

  // Settings
  deepgramApiKey: string
  openaiApiKey: string
  captureSystemAudio: boolean
  captureMicrophone: boolean
  deepgramModel: DeepgramModel
  openaiModel: OpenAIModel

  // Managed mode
  usageInfo: UsageInfo | null
  isLoadingUsage: boolean
  managedSessionError: string | null
  currentSessionId: string | null
  tempDeepgramKey: string | null

  // Selected tab in recording view
  selectedTab: 'transcript' | 'insights'

  // History
  selectedMeetingId: string | null

  // --- Actions ---
  loadSettings: () => Promise<void>
  saveSetting: (key: string, value: unknown) => Promise<void>

  startNewMeeting: () => Promise<void>
  startRecording: () => Promise<void>
  stopRecording: () => Promise<void>
  resumeRecording: () => Promise<void>
  goHome: () => Promise<void>

  handleTranscriptUpdate: (update: TranscriptUpdate) => void

  refreshUsage: () => Promise<void>
  setInsightsMode: (mode: InsightsMode) => void
  setSelectedTab: (tab: 'transcript' | 'insights') => void
  setLiveNotes: (notes: string) => void
  setSelectedMeetingId: (id: string | null) => void

  startAudioMonitoring: () => Promise<void>
  stopAudioMonitoring: () => void
}

// --- Timer ---
let recordingTimer: ReturnType<typeof setInterval> | null = null
let recordingStartDate: Date | null = null
let lastInsightSegmentCount = 0

// Generate meeting title (matches macOS format)
function generateMeetingTitle(): string {
  const d = new Date()
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
}

export const useStore = create<AppStore>((set, get) => ({
  // --- Initial state ---
  view: 'home',
  appMode: 'managed',
  hasCompletedOnboarding: false,
  isRecording: false,
  recordingDuration: 0,
  hasUnsavedSession: false,
  connectionState: 'disconnected',
  currentMeetingId: null,
  currentMeetingTitle: '',
  liveSegments: [],
  interimText: '',
  currentSpeaker: 0,
  interimSpeaker: null,
  detectedSpeakers: new Set(),
  microphoneLevel: 0,
  systemAudioLevel: 0,
  isMonitoring: false,
  insightsMode: 'standard',
  isGeneratingInsights: false,
  liveSummary: '',
  liveActionItems: [],
  liveTopics: [],
  liveDiscussionFlow: [],
  liveNotes: '',
  deepgramApiKey: '',
  openaiApiKey: '',
  captureSystemAudio: true,
  captureMicrophone: true,
  deepgramModel: 'nova-3',
  openaiModel: 'gpt-5-mini-2025-08-07',
  usageInfo: null,
  isLoadingUsage: false,
  managedSessionError: null,
  currentSessionId: null,
  tempDeepgramKey: null,
  selectedTab: 'transcript',
  selectedMeetingId: null,

  // --- Actions ---

  loadSettings: async () => {
    const all = await window.api.getAllSettings()
    set({
      appMode: (all.appMode as AppMode) || 'managed',
      hasCompletedOnboarding: (all.hasCompletedOnboarding as boolean) || false,
      deepgramApiKey: (all.deepgramApiKey as string) || '',
      openaiApiKey: (all.openaiApiKey as string) || '',
      captureSystemAudio: all.captureSystemAudio !== false,
      captureMicrophone: all.captureMicrophone !== false,
      deepgramModel: (all.deepgramModel as DeepgramModel) || 'nova-3',
      openaiModel: (all.openaiModel as OpenAIModel) || 'gpt-5-mini-2025-08-07',
      insightsMode: (all.insightsMode as InsightsMode) || 'standard',
      view: all.hasCompletedOnboarding ? 'home' : 'onboarding'
    })
  },

  saveSetting: async (key: string, value: unknown) => {
    await window.api.setSetting(key, value)
    set({ [key]: value } as Partial<AppStore>)
  },

  completeOnboarding: async (mode: AppMode) => {
    await window.api.setSetting('hasCompletedOnboarding', true)
    await window.api.setSetting('appMode', mode)
    set({ hasCompletedOnboarding: true, appMode: mode, view: 'home' })
    if (mode === 'managed') {
      get().refreshUsage()
    }
  },

  startNewMeeting: async () => {
    const state = get()

    // Mode-aware guard
    if (state.appMode === 'byok' && !state.deepgramApiKey) {
      set({ view: 'settings' })
      return
    }
    if (state.appMode === 'managed' && state.usageInfo?.isLimitReached) {
      return
    }

    // Save previous meeting if exists
    await saveMeetingIfNeeded(get)

    // Create new meeting
    const id = crypto.randomUUID()
    const title = generateMeetingTitle()
    lastInsightSegmentCount = 0

    set({
      currentMeetingId: id,
      currentMeetingTitle: title,
      liveSegments: [],
      interimText: '',
      interimSpeaker: null,
      detectedSpeakers: new Set(),
      recordingDuration: 0,
      hasUnsavedSession: true,
      managedSessionError: null,
      liveNotes: '',
      liveSummary: '',
      liveActionItems: [],
      liveTopics: [],
      liveDiscussionFlow: [],
      liveMetrics: undefined,
      liveEconomicBuyer: undefined,
      liveDecisionCriteria: undefined,
      liveDecisionProcess: undefined,
      livePaperProcess: undefined,
      liveIdentifiedPain: undefined,
      liveChampion: undefined,
      liveCompetition: undefined,
      view: 'recording',
      selectedTab: 'transcript'
    })

    if (state.appMode === 'managed') {
      await startManagedRecording(get, set)
    } else {
      await get().startRecording()
    }
  },

  startRecording: async () => {
    const state = get()

    // Stop monitoring if active
    if (state.isMonitoring) {
      get().stopAudioMonitoring()
    }

    // Determine API key
    const apiKey =
      state.appMode === 'managed' && state.tempDeepgramKey
        ? state.tempDeepgramKey
        : state.deepgramApiKey

    if (!apiKey) {
      set({ managedSessionError: 'No API key available' })
      return
    }

    // Connect to Deepgram via main process
    await window.api.deepgramConnect(apiKey, state.deepgramModel)

    // Start audio capture in renderer
    await startAudioCapture(state.captureMicrophone, state.captureSystemAudio, set)

    // Start recording timer
    if (!recordingStartDate) {
      recordingStartDate = new Date()
    }
    recordingTimer = setInterval(() => {
      if (recordingStartDate) {
        set({ recordingDuration: (Date.now() - recordingStartDate.getTime()) / 1000 })
      }
    }, 1000)

    set({ isRecording: true })
  },

  stopRecording: async () => {
    set({ isRecording: false })

    // Stop timer
    if (recordingTimer) {
      clearInterval(recordingTimer)
      recordingTimer = null
    }

    // Stop audio capture
    stopAudioCapture()

    // Disconnect Deepgram
    await window.api.deepgramDisconnect()

    const state = get()

    // Report usage in managed mode
    if (state.appMode === 'managed' && state.currentSessionId) {
      const deviceId = await window.api.getDeviceId()
      const durationMin = state.recordingDuration / 60
      try {
        await window.api.endSession(deviceId, state.currentSessionId, durationMin)
        get().refreshUsage()
      } catch (err) {
        console.error('[Store] Failed to report session end:', err)
      }
      set({ currentSessionId: null, tempDeepgramKey: null })
    }

    // Save meeting
    await saveMeetingIfNeeded(get)

    // Generate final insights if we have content but no summary
    const finalSegments = state.liveSegments.filter(
      (s) => s.isFinal && s.text.trim().length > 0
    )
    if (finalSegments.length > 0 && !state.liveSummary) {
      await generateInsightsForCurrentMeeting(get, set)
    }
  },

  resumeRecording: async () => {
    const state = get()
    if (state.appMode === 'managed') {
      await startManagedRecording(get, set)
    } else {
      await get().startRecording()
    }
  },

  goHome: async () => {
    const state = get()
    if (state.isRecording) {
      await get().stopRecording()
    }
    await saveMeetingIfNeeded(get)
    clearSession(set)
    set({ view: 'home', insightsMode: 'standard' })
  },

  handleTranscriptUpdate: (update: TranscriptUpdate) => {
    const state = get()

    if (!update.text.trim()) return

    if (update.isFinal) {
      // Process speaker segments
      const finalSegments = update.segments.filter((s) => s.isFinal)
      const newDetected = new Set(state.detectedSpeakers)

      const newLiveSegments = [...state.liveSegments.filter((s) => s.isFinal)]

      for (const seg of finalSegments) {
        const text = seg.text.trim()
        if (!text) continue

        newDetected.add(seg.speaker)

        // Check for duplicates
        const isDup = newLiveSegments.slice(-3).some(
          (s) =>
            s.isFinal &&
            s.speaker === seg.speaker &&
            (s.text === text || s.text.includes(text) || text.includes(s.text))
        )

        if (!isDup) {
          newLiveSegments.push({
            id: seg.id,
            text,
            speaker: seg.speaker,
            timestamp: state.recordingDuration,
            isFinal: true
          })
        }
      }

      set({
        liveSegments: newLiveSegments,
        interimText: '',
        interimSpeaker: null,
        detectedSpeakers: newDetected
      })

      // Check if we should update insights
      const finalCount = newLiveSegments.filter(
        (s) => s.isFinal && s.text.trim().length > 0
      ).length
      const threshold = lastInsightSegmentCount === 0 ? 3 : 5
      if (finalCount >= lastInsightSegmentCount + threshold) {
        lastInsightSegmentCount = finalCount
        generateInsightsForCurrentMeeting(get, set)
      }
    } else {
      // Interim result
      const newDetected = new Set(state.detectedSpeakers)
      newDetected.add(update.speaker)
      set({
        interimText: update.text,
        currentSpeaker: update.speaker,
        interimSpeaker: update.speaker,
        detectedSpeakers: newDetected
      })
    }
  },

  refreshUsage: async () => {
    const state = get()
    if (state.appMode !== 'managed') return

    set({ isLoadingUsage: true })
    try {
      const deviceId = await window.api.getDeviceId()
      const usage = await window.api.checkUsage(deviceId)
      set({ usageInfo: usage })
    } catch (err) {
      console.error('[Store] Failed to check usage:', err)
    }
    set({ isLoadingUsage: false })
  },

  setInsightsMode: (mode: InsightsMode) => {
    set({ insightsMode: mode })
    window.api.setSetting('insightsMode', mode)
  },

  setSelectedTab: (tab: 'transcript' | 'insights') => set({ selectedTab: tab }),
  setLiveNotes: (notes: string) => set({ liveNotes: notes }),
  setSelectedMeetingId: (id: string | null) => set({ selectedMeetingId: id }),

  startAudioMonitoring: async () => {
    if (get().isRecording) return
    set({ isMonitoring: true })
    const state = get()
    await startAudioCapture(state.captureMicrophone, state.captureSystemAudio, set, true)
  },

  stopAudioMonitoring: () => {
    stopAudioCapture()
    set({ isMonitoring: false, microphoneLevel: 0, systemAudioLevel: 0 })
  },

  setView: (view: AppView) => set({ view })
}))

// --- Helper functions ---

async function startManagedRecording(
  get: () => AppStore,
  set: (partial: Partial<AppStore>) => void
): Promise<void> {
  const state = get()
  try {
    const deviceId = await window.api.getDeviceId()
    const session = await window.api.requestSession(deviceId, state.deepgramModel)
    set({
      currentSessionId: session.sessionId,
      tempDeepgramKey: session.tempApiKey
    })
    await get().startRecording()
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to start session'
    if (msg.startsWith('limit_reached')) {
      get().refreshUsage()
    }
    set({ managedSessionError: msg })
    console.error('[Store] Managed session failed:', err)
  }
}

async function startAudioCapture(
  captureMic: boolean,
  captureSystem: boolean,
  set: (partial: Partial<AppStore>) => void,
  monitorOnly = false
): Promise<void> {
  // Mic capture
  if (captureMic) {
    try {
      micStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false
        }
      })
      micAudioContext = new AudioContext({ sampleRate: 16000 })
      micSource = micAudioContext.createMediaStreamSource(micStream)
      micProcessor = micAudioContext.createScriptProcessorNode(4096, 1, 1)

      micProcessor.onaudioprocess = (e) => {
        const float32 = e.inputBuffer.getChannelData(0)

        // Calculate level (RMS)
        let sum = 0
        for (let i = 0; i < float32.length; i++) {
          sum += float32[i] * float32[i]
        }
        const rms = Math.sqrt(sum / float32.length)
        set({ microphoneLevel: rms })

        if (!monitorOnly) {
          // Convert float32 to int16 PCM
          const int16 = new Int16Array(float32.length)
          for (let i = 0; i < float32.length; i++) {
            const s = Math.max(-1, Math.min(1, float32[i]))
            int16[i] = s < 0 ? s * 0x8000 : s * 0x7fff
          }
          window.api.deepgramSendAudio(int16.buffer)
        }
      }

      micSource.connect(micProcessor)
      micProcessor.connect(micAudioContext.destination)
    } catch (err) {
      console.error('[Audio] Failed to start mic capture:', err)
    }
  }

  // System audio capture via desktopCapturer
  if (captureSystem) {
    try {
      const sources = await window.api.getDesktopSources()
      if (sources.length > 0) {
        // On Windows, we need to request media with the screen source to get system audio.
        // We capture both video+audio but only use the audio track.
        sysStream = await navigator.mediaDevices.getUserMedia({
          audio: {
            // @ts-expect-error — Electron-specific constraint for desktop audio
            mandatory: {
              chromeMediaSource: 'desktop',
              chromeMediaSourceId: sources[0].id
            }
          },
          video: {
            // @ts-expect-error — Electron-specific constraint
            mandatory: {
              chromeMediaSource: 'desktop',
              chromeMediaSourceId: sources[0].id,
              maxWidth: 1,
              maxHeight: 1,
              maxFrameRate: 1
            }
          }
        })

        // Stop video tracks immediately (we only want audio)
        sysStream.getVideoTracks().forEach((t) => t.stop())

        const audioTracks = sysStream.getAudioTracks()
        if (audioTracks.length > 0) {
          sysAudioContext = new AudioContext({ sampleRate: 16000 })
          const audioOnlyStream = new MediaStream(audioTracks)
          sysSource = sysAudioContext.createMediaStreamSource(audioOnlyStream)
          sysProcessor = sysAudioContext.createScriptProcessorNode(4096, 1, 1)

          sysProcessor.onaudioprocess = (e) => {
            const float32 = e.inputBuffer.getChannelData(0)
            let sum = 0
            for (let i = 0; i < float32.length; i++) {
              sum += float32[i] * float32[i]
            }
            const rms = Math.sqrt(sum / float32.length)
            set({ systemAudioLevel: rms })

            if (!monitorOnly) {
              const int16 = new Int16Array(float32.length)
              for (let i = 0; i < float32.length; i++) {
                const s = Math.max(-1, Math.min(1, float32[i]))
                int16[i] = s < 0 ? s * 0x8000 : s * 0x7fff
              }
              // TODO: mix with mic audio before sending, or send separately
              // For now, system audio is sent separately (Deepgram gets interleaved)
              window.api.deepgramSendAudio(int16.buffer)
            }
          }

          sysSource.connect(sysProcessor)
          sysProcessor.connect(sysAudioContext.destination)
        }
      }
    } catch (err) {
      console.error('[Audio] Failed to start system audio capture:', err)
    }
  }
}

function stopAudioCapture(): void {
  // Mic cleanup
  micProcessor?.disconnect()
  micSource?.disconnect()
  micAudioContext?.close()
  micStream?.getTracks().forEach((t) => t.stop())
  micProcessor = null
  micSource = null
  micAudioContext = null
  micStream = null

  // System cleanup
  sysProcessor?.disconnect()
  sysSource?.disconnect()
  sysAudioContext?.close()
  sysStream?.getTracks().forEach((t) => t.stop())
  sysProcessor = null
  sysSource = null
  sysAudioContext = null
  sysStream = null
}

async function saveMeetingIfNeeded(get: () => AppStore): Promise<void> {
  const state = get()
  if (!state.currentMeetingId) return

  const finalSegments = state.liveSegments.filter(
    (s) => s.isFinal && s.text.trim().length > 0
  )
  if (finalSegments.length === 0) return

  const meeting: Meeting = {
    id: state.currentMeetingId,
    title: state.currentMeetingTitle,
    startTime: recordingStartDate?.toISOString() || new Date().toISOString(),
    endTime: new Date().toISOString(),
    summaryText: state.liveSummary || undefined,
    actionItems: state.liveActionItems,
    keyDecisions: [],
    topics: state.liveTopics,
    discussionFlow: state.liveDiscussionFlow,
    notes: state.liveNotes,
    meddpiccMetrics: state.liveMetrics,
    meddpiccEconomicBuyer: state.liveEconomicBuyer,
    meddpiccDecisionCriteria: state.liveDecisionCriteria,
    meddpiccDecisionProcess: state.liveDecisionProcess,
    meddpiccPaperProcess: state.livePaperProcess,
    meddpiccIdentifiedPain: state.liveIdentifiedPain,
    meddpiccChampion: state.liveChampion,
    meddpiccCompetition: state.liveCompetition
  }

  const segments = finalSegments.map((s) => ({
    id: s.id,
    meetingId: state.currentMeetingId!,
    text: s.text,
    speaker: s.speaker,
    timestamp: s.timestamp,
    isFinal: true,
    confidence: 1.0
  }))

  await window.api.saveMeeting(meeting, segments)
}

function clearSession(set: (partial: Partial<AppStore>) => void): void {
  recordingStartDate = null
  lastInsightSegmentCount = 0
  if (recordingTimer) {
    clearInterval(recordingTimer)
    recordingTimer = null
  }
  stopAudioCapture()

  set({
    currentMeetingId: null,
    currentMeetingTitle: '',
    liveSegments: [],
    interimText: '',
    interimSpeaker: null,
    detectedSpeakers: new Set(),
    recordingDuration: 0,
    hasUnsavedSession: false,
    isRecording: false,
    liveNotes: '',
    liveSummary: '',
    liveActionItems: [],
    liveTopics: [],
    liveDiscussionFlow: [],
    liveMetrics: undefined,
    liveEconomicBuyer: undefined,
    liveDecisionCriteria: undefined,
    liveDecisionProcess: undefined,
    livePaperProcess: undefined,
    liveIdentifiedPain: undefined,
    liveChampion: undefined,
    liveCompetition: undefined,
    currentSessionId: null,
    tempDeepgramKey: null,
    managedSessionError: null
  })
}

async function generateInsightsForCurrentMeeting(
  get: () => AppStore,
  set: (partial: Partial<AppStore>) => void
): Promise<void> {
  const state = get()
  if (state.isGeneratingInsights) return

  const finalSegments = state.liveSegments
    .filter((s) => s.isFinal && s.text.trim().length > 0)
    .sort((a, b) => a.timestamp - b.timestamp)

  const transcript = finalSegments
    .map((s) => {
      const label = s.speaker === MIC_SPEAKER_ID ? 'You' : `Speaker ${s.speaker + 1}`
      return `[${label}] ${s.text}`
    })
    .join('\n')

  if (!transcript) return

  set({ isGeneratingInsights: true })

  try {
    let insights: import('./types').LiveInsights

    if (state.appMode === 'managed') {
      const deviceId = await window.api.getDeviceId()
      insights = await window.api.apiGenerateInsights({
        deviceId,
        transcript,
        existingSummary: state.liveSummary || undefined,
        existingTitle: undefined,
        mode: state.insightsMode,
        model: state.openaiModel
      })
    } else {
      if (!state.openaiApiKey) {
        set({ isGeneratingInsights: false })
        return
      }
      insights = await window.api.generateLiveInsights({
        transcript,
        existingSummary: state.liveSummary || undefined,
        existingTitle: undefined,
        mode: state.insightsMode,
        model: state.openaiModel,
        apiKey: state.openaiApiKey
      })
    }

    set({
      liveSummary: insights.summary || '',
      liveActionItems: insights.actionItems || [],
      liveTopics: insights.topics || [],
      liveDiscussionFlow: insights.discussionFlow || [],
      liveMetrics: insights.metrics,
      liveEconomicBuyer: insights.economicBuyer,
      liveDecisionCriteria: insights.decisionCriteria,
      liveDecisionProcess: insights.decisionProcess,
      livePaperProcess: insights.paperProcess,
      liveIdentifiedPain: insights.identifiedPain,
      liveChampion: insights.champion,
      liveCompetition: insights.competition
    })

    // Update meeting title if we got a suggestion
    if (insights.suggestedTitle) {
      const state2 = get()
      const timestamp = state2.currentMeetingTitle.split(' - ')[0] || state2.currentMeetingTitle
      set({ currentMeetingTitle: `${timestamp} - ${insights.suggestedTitle}` })
    }
  } catch (err) {
    console.error('[Insights] Error:', err)
  }

  set({ isGeneratingInsights: false })
}
