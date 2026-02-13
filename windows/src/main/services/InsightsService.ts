// --- Types ---

export type OpenAIModel = 'gpt-5-mini-2025-08-07' | 'gpt-5-nano-2025-08-07'
export type InsightsMode = 'standard' | 'meddpicc'

export interface LiveInsights {
  summary: string
  actionItems: string[]
  topics: string[]
  discussionFlow: string[]
  suggestedTitle?: string
  // MEDDPICC fields
  metrics?: string
  economicBuyer?: string
  decisionCriteria?: string
  decisionProcess?: string
  paperProcess?: string
  identifiedPain?: string
  champion?: string
  competition?: string
}

export interface MeetingInsights {
  summary: string
  actionItems: string[]
  decisions: string[]
  topics: string[]
}

// --- Service ---

export class InsightsService {
  async generateLiveInsights(opts: {
    transcript: string
    existingSummary?: string
    existingTitle?: string
    mode?: InsightsMode
    model?: OpenAIModel
    apiKey: string
  }): Promise<LiveInsights> {
    const {
      transcript,
      existingSummary,
      existingTitle,
      mode = 'standard',
      model = 'gpt-5-mini-2025-08-07',
      apiKey
    } = opts

    if (!transcript.trim()) throw new Error('No transcript to analyze')

    const contextNote = existingSummary
      ? `Previous summary: "${existingSummary}"\n\nUpdate this summary with new information from the transcript below. Keep it concise (2-3 sentences max).`
      : 'This is the start of the meeting. Provide a brief summary.'

    const needsTitle = !existingTitle
    const titleInstruction = needsTitle
      ? '"title": "Short descriptive title for this meeting (3-6 words)",'
      : ''

    let systemPrompt: string
    let prompt: string

    if (mode === 'meddpicc') {
      systemPrompt =
        'You are a sales qualification analyst using the MEDDPICC framework. Extract qualification insights from sales conversations. Be concise but thorough on qualification criteria.'
      prompt = `Analyze this sales call using the MEDDPICC framework. Extract any information mentioned.

${contextNote}

MEDDPICC Framework:
- Metrics: Quantifiable success measures the prospect mentioned
- Economic Buyer: Who controls budget/final decision
- Decision Criteria: Factors influencing their decision
- Decision Process: Their buying/evaluation process
- Paper Process: Legal, procurement, security review steps
- Identify Pain: Problems they're trying to solve
- Champion: Internal advocate for your solution
- Competition: Other solutions they're considering

Respond in JSON (use null for fields with no information yet):
{
    ${titleInstruction}
    "summary": "Brief summary of the sales conversation",
    "action_items": ["Follow-up actions needed"],
    "topics": ["Broad themes discussed (1-2 words each)"],
    "metrics": "What success metrics were mentioned (or null)",
    "economic_buyer": "Who is the economic buyer (or null)",
    "decision_criteria": "What decision criteria were mentioned (or null)",
    "decision_process": "What's their decision process (or null)",
    "paper_process": "What's their paper/procurement process (or null)",
    "identified_pain": "What pain points were identified (or null)",
    "champion": "Who could be a champion (or null)",
    "competition": "What competitors were mentioned (or null)"
}

Latest transcript:
${transcript}`
    } else {
      systemPrompt =
        'You provide real-time meeting summaries. Be extremely concise. Focus on what\'s being discussed RIGHT NOW.'
      prompt = `You are providing LIVE meeting insights. Be very concise.

${contextNote}

Respond in JSON:
{
    ${titleInstruction}
    "summary": "Brief 1-2 sentence summary of what's being discussed",
    "action_items": ["Any action items mentioned (keep short)"],
    "topics": ["Broad themes/categories being discussed (1-2 words each, max 4 topics)"],
    "discussion_flow": ["Chronological list of what was discussed, in order"]
}

Latest transcript:
${transcript}`
    }

    const body = {
      model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: prompt }
      ],
      max_completion_tokens: 10000,
      response_format: { type: 'json_object' }
    }

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    })

    if (!res.ok) {
      const errBody = await res.json().catch(() => null)
      throw new Error(errBody?.error?.message || `OpenAI HTTP ${res.status}`)
    }

    const data = await res.json()
    const content = data.choices?.[0]?.message?.content
    if (!content) throw new Error('No content in OpenAI response')

    const parsed = JSON.parse(content)

    return {
      summary: parsed.summary || '',
      actionItems: parsed.action_items || [],
      topics: parsed.topics || [],
      discussionFlow: parsed.discussion_flow || [],
      suggestedTitle: parsed.title || undefined,
      metrics: parsed.metrics || undefined,
      economicBuyer: parsed.economic_buyer || undefined,
      decisionCriteria: parsed.decision_criteria || undefined,
      decisionProcess: parsed.decision_process || undefined,
      paperProcess: parsed.paper_process || undefined,
      identifiedPain: parsed.identified_pain || undefined,
      champion: parsed.champion || undefined,
      competition: parsed.competition || undefined
    }
  }

  async generateInsights(opts: {
    transcript: string
    model?: OpenAIModel
    apiKey: string
  }): Promise<MeetingInsights> {
    const { transcript, model = 'gpt-5-mini-2025-08-07', apiKey } = opts

    if (!transcript.trim()) throw new Error('No transcript to analyze')

    const body = {
      model,
      messages: [
        {
          role: 'system',
          content:
            'You are a meeting analyst. Provide concise, actionable insights from meeting transcripts. Always respond with valid JSON.'
        },
        {
          role: 'user',
          content: `Analyze this meeting transcript and provide structured insights.

Respond in JSON format:
{
    "summary": "A 2-3 sentence summary of the meeting",
    "action_items": ["List of action items mentioned"],
    "decisions": ["Key decisions made during the meeting"],
    "topics": ["Broad themes/categories (1-2 words each)"]
}

Transcript:
${transcript}`
        }
      ],
      max_completion_tokens: 1000,
      response_format: { type: 'json_object' }
    }

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    })

    if (!res.ok) {
      const errBody = await res.json().catch(() => null)
      throw new Error(errBody?.error?.message || `OpenAI HTTP ${res.status}`)
    }

    const data = await res.json()
    const content = data.choices?.[0]?.message?.content
    if (!content) throw new Error('No content in OpenAI response')

    const parsed = JSON.parse(content)

    return {
      summary: parsed.summary || '',
      actionItems: parsed.action_items || [],
      decisions: parsed.decisions || [],
      topics: parsed.topics || []
    }
  }
}
