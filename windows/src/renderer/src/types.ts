// --- Shared types between main and renderer ---

import type { API } from '../../preload/index'

declare global {
  interface Window {
    api: API
  }
}

export type AppMode = 'byok' | 'managed'
export type InsightsMode = 'standard' | 'meddpicc'
export type DeepgramModel = 'nova-2' | 'nova-3'
export type OpenAIModel = 'gpt-5-mini-2025-08-07' | 'gpt-5-nano-2025-08-07'
export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error'
export type AppView = 'onboarding' | 'home' | 'recording' | 'history' | 'settings'

export interface LiveSegment {
  id: string
  text: string
  speaker: number
  timestamp: number
  isFinal: boolean
}

export interface TranscriptUpdate {
  text: string
  speaker: number
  isFinal: boolean
  confidence: number
  words: Array<{
    text: string
    start: number
    end: number
    confidence: number
    speaker: number
  }>
  segments: Array<{
    id: string
    speaker: number
    text: string
    startTime: number
    endTime: number
    isFinal: boolean
    confidence: number
  }>
}

export interface UsageInfo {
  minutesUsed: number
  minutesLimit: number
  resetsAt: string
  tier: string
  minutesRemaining: number
  isLimitReached: boolean
}

export interface Meeting {
  id: string
  title: string
  startTime: string
  endTime?: string
  summaryText?: string
  actionItems: string[]
  keyDecisions: string[]
  topics: string[]
  discussionFlow: string[]
  notes: string
  meddpiccMetrics?: string
  meddpiccEconomicBuyer?: string
  meddpiccDecisionCriteria?: string
  meddpiccDecisionProcess?: string
  meddpiccPaperProcess?: string
  meddpiccIdentifiedPain?: string
  meddpiccChampion?: string
  meddpiccCompetition?: string
  segments?: Array<{
    id: string
    meetingId: string
    text: string
    speaker: number
    timestamp: number
    isFinal: boolean
    confidence: number
  }>
}

export interface LiveInsights {
  summary: string
  actionItems: string[]
  topics: string[]
  discussionFlow: string[]
  suggestedTitle?: string
  metrics?: string
  economicBuyer?: string
  decisionCriteria?: string
  decisionProcess?: string
  paperProcess?: string
  identifiedPain?: string
  champion?: string
  competition?: string
}

// Model display info
export const DEEPGRAM_MODELS: Record<DeepgramModel, { display: string; short: string }> = {
  'nova-2': { display: 'Nova-2', short: 'faster' },
  'nova-3': { display: 'Nova-3', short: 'smarter' }
}

export const OPENAI_MODELS: Record<OpenAIModel, { display: string; short: string }> = {
  'gpt-5-mini-2025-08-07': { display: 'GPT-5 Mini', short: '5-mini' },
  'gpt-5-nano-2025-08-07': { display: 'GPT-5 Nano', short: '5-nano' }
}

/** Reserved speaker ID for local microphone ("You") */
export const MIC_SPEAKER_ID = 1000
