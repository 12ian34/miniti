// --- Types ---

export interface UsageInfo {
  minutesUsed: number
  minutesLimit: number
  resetsAt: string // ISO date
  tier: string
  minutesRemaining: number
  isLimitReached: boolean
}

export interface SessionResponse {
  tempApiKey: string
  expiresAt: string
  sessionId: string
}

export interface EndSessionResponse {
  minutesUsed: number
  minutesRemaining: number
}

export interface ManagedInsightsResponse {
  summary: string
  actionItems: string[]
  topics: string[]
  discussionFlow: string[]
  title?: string
  metrics?: string
  economicBuyer?: string
  decisionCriteria?: string
  decisionProcess?: string
  paperProcess?: string
  identifiedPain?: string
  champion?: string
  competition?: string
}

// --- Service ---

const BASE_URL = process.env.MINITI_API_URL || 'https://miniti-api.vercel.app/api'

/**
 * XOR-obfuscated shared app secret (same as macOS version).
 * Not truly secret — just keeps the key out of plain text in source/binary.
 */
function getApiKey(): string {
  const mask = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xb4, 0x74, 0x28, 0xae, 0x7f, 0x38, 0xdd,
    0xc7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xbb, 0xe2, 0x6e, 0xe1, 0x44, 0xbc,
    0x6b, 0x2c
  ]
  const obfuscated = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0xbb, 0x1a, 0x9a, 0x02, 0x09, 0x84,
    0xe6, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7f, 0x18, 0xa2, 0x5f, 0x3f, 0x42,
    0xc5, 0x54
  ]
  return obfuscated
    .map((b, i) => (b ^ mask[i]).toString(16).padStart(2, '0'))
    .join('')
}

function makeHeaders(deviceId: string): Record<string, string> {
  return {
    'X-API-Key': getApiKey(),
    'X-Device-ID': deviceId,
    'Content-Type': 'application/json'
  }
}

function parseNumeric(val: unknown): number {
  if (typeof val === 'number') return val
  if (typeof val === 'string') return parseFloat(val) || 0
  return 0
}

export class MinitiAPIService {
  async checkUsage(deviceId: string): Promise<UsageInfo> {
    const res = await fetch(`${BASE_URL}/usage`, {
      headers: makeHeaders(deviceId)
    })
    await this.validateResponse(res)
    const data = await res.json()

    const minutesUsed = parseNumeric(data.minutes_used)
    const minutesLimit = parseNumeric(data.minutes_limit) || 500

    return {
      minutesUsed,
      minutesLimit,
      resetsAt: data.resets_at,
      tier: data.tier,
      minutesRemaining: Math.max(0, minutesLimit - minutesUsed),
      isLimitReached: minutesUsed >= minutesLimit
    }
  }

  async requestSession(deviceId: string, model: string): Promise<SessionResponse> {
    const res = await fetch(`${BASE_URL}/session`, {
      method: 'POST',
      headers: makeHeaders(deviceId),
      body: JSON.stringify({ model })
    })
    await this.validateResponse(res)
    const data = await res.json()
    return {
      tempApiKey: data.temp_api_key,
      expiresAt: data.expires_at,
      sessionId: data.session_id
    }
  }

  async endSession(
    deviceId: string,
    sessionId: string,
    durationMinutes: number
  ): Promise<EndSessionResponse> {
    const res = await fetch(`${BASE_URL}/session/end`, {
      method: 'POST',
      headers: makeHeaders(deviceId),
      body: JSON.stringify({
        session_id: sessionId,
        duration_minutes: durationMinutes
      })
    })
    await this.validateResponse(res)
    const data = await res.json()
    return {
      minutesUsed: parseNumeric(data.minutes_used),
      minutesRemaining: parseNumeric(data.minutes_remaining)
    }
  }

  async generateInsights(opts: {
    deviceId: string
    transcript: string
    existingSummary?: string
    existingTitle?: string
    mode: string
    model: string
  }): Promise<ManagedInsightsResponse> {
    const body: Record<string, string> = {
      transcript: opts.transcript,
      mode: opts.mode,
      model: opts.model
    }
    if (opts.existingSummary) body.existing_summary = opts.existingSummary
    if (opts.existingTitle) body.existing_title = opts.existingTitle

    const res = await fetch(`${BASE_URL}/insights`, {
      method: 'POST',
      headers: makeHeaders(opts.deviceId),
      body: JSON.stringify(body)
    })
    await this.validateResponse(res)
    const data = await res.json()

    return {
      summary: data.summary || '',
      actionItems: data.action_items || [],
      topics: data.topics || [],
      discussionFlow: data.discussion_flow || [],
      title: data.title || undefined,
      metrics: data.metrics || undefined,
      economicBuyer: data.economic_buyer || undefined,
      decisionCriteria: data.decision_criteria || undefined,
      decisionProcess: data.decision_process || undefined,
      paperProcess: data.paper_process || undefined,
      identifiedPain: data.identified_pain || undefined,
      champion: data.champion || undefined,
      competition: data.competition || undefined
    }
  }

  private async validateResponse(res: Response): Promise<void> {
    if (res.ok) return

    const body = await res.json().catch(() => null)

    if (res.status === 402) {
      throw new Error(
        `limit_reached:${body?.minutes_used ?? 500}:${body?.resets_at ?? ''}`
      )
    }
    if (res.status === 429) {
      throw new Error('rate_limited')
    }
    throw new Error(body?.message || body?.error || `HTTP ${res.status}`)
  }
}
