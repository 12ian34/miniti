import { useStore } from '../store'
import { colors } from '../colors'
import type { InsightsMode } from '../types'

export function InsightsView() {
  const insightsMode = useStore((s) => s.insightsMode)
  const setInsightsMode = useStore((s) => s.setInsightsMode)
  const isGenerating = useStore((s) => s.isGeneratingInsights)
  const summary = useStore((s) => s.liveSummary)
  const actionItems = useStore((s) => s.liveActionItems)
  const topics = useStore((s) => s.liveTopics)
  const discussionFlow = useStore((s) => s.liveDiscussionFlow)

  // MEDDPICC
  const metrics = useStore((s) => s.liveMetrics)
  const economicBuyer = useStore((s) => s.liveEconomicBuyer)
  const decisionCriteria = useStore((s) => s.liveDecisionCriteria)
  const decisionProcess = useStore((s) => s.liveDecisionProcess)
  const paperProcess = useStore((s) => s.livePaperProcess)
  const identifiedPain = useStore((s) => s.liveIdentifiedPain)
  const champion = useStore((s) => s.liveChampion)
  const competition = useStore((s) => s.liveCompetition)

  const modes: { id: InsightsMode; label: string }[] = [
    { id: 'standard', label: 'standard' },
    { id: 'meddpicc', label: 'MEDDPICC' }
  ]

  const hasNoContent =
    !summary && actionItems.length === 0 && topics.length === 0 && discussionFlow.length === 0

  const meddpiccFields: Array<{ key: string; label: string; value?: string; color: string }> = [
    { key: 'M', label: 'Metrics', value: metrics, color: colors.meddpicc.M },
    { key: 'E', label: 'Economic Buyer', value: economicBuyer, color: colors.meddpicc.E },
    { key: 'D', label: 'Decision Criteria', value: decisionCriteria, color: colors.meddpicc.D },
    { key: 'D', label: 'Decision Process', value: decisionProcess, color: colors.meddpicc.D },
    { key: 'P', label: 'Paper Process', value: paperProcess, color: colors.meddpicc.P },
    { key: 'I', label: 'Identified Pain', value: identifiedPain, color: colors.meddpicc.I },
    { key: 'C', label: 'Champion', value: champion, color: colors.meddpicc.C },
    { key: 'C', label: 'Competition', value: competition, color: colors.meddpicc.C }
  ]

  return (
    <div className="flex flex-col h-full" style={{ backgroundColor: colors.bg.primary }}>
      {/* Mode selector */}
      <div
        className="flex items-center gap-2 px-4 py-2 border-b"
        style={{ borderColor: colors.border.primary, backgroundColor: colors.bg.panel }}
      >
        <span className="text-[10px] font-mono font-medium" style={{ color: colors.text.subtle }}>
          mode:
        </span>
        {modes.map((m) => (
          <button
            key={m.id}
            onClick={() => setInsightsMode(m.id)}
            className="text-[10px] font-mono font-semibold px-2 py-0.5 rounded transition-colors"
            style={{
              color: insightsMode === m.id ? colors.text.primary : colors.text.disabled,
              backgroundColor: insightsMode === m.id ? colors.bg.card : 'transparent'
            }}
          >
            {m.label}
          </button>
        ))}
        {isGenerating && (
          <span className="text-[10px] font-mono ml-auto" style={{ color: colors.accent.amber }}>
            analyzing...
          </span>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
        {hasNoContent ? (
          <div className="flex flex-col items-center justify-center h-full gap-3">
            <span className="text-4xl" style={{ color: colors.border.primary }}>
              ◇
            </span>
            <span className="text-xs font-mono" style={{ color: colors.text.meta }}>
              insights will appear as the meeting progresses
            </span>
          </div>
        ) : (
          <>
            {/* Summary */}
            {summary && (
              <Section title="summary" color={colors.accent.blueGH}>
                <p className="text-xs font-mono leading-relaxed" style={{ color: colors.text.secondary }}>
                  {summary}
                </p>
              </Section>
            )}

            {/* Discussion Flow */}
            {discussionFlow.length > 0 && (
              <Section title="discussion flow" color={colors.accent.amber}>
                <ol className="space-y-1">
                  {discussionFlow.map((item, i) => (
                    <li key={i} className="flex items-start gap-2">
                      <span className="text-[10px] font-mono mt-0.5" style={{ color: colors.text.disabled }}>
                        {i + 1}.
                      </span>
                      <span className="text-xs font-mono leading-relaxed" style={{ color: colors.text.secondary }}>
                        {item}
                      </span>
                    </li>
                  ))}
                </ol>
              </Section>
            )}

            {/* Action Items */}
            {actionItems.length > 0 && (
              <Section title="action items" color={colors.accent.greenGH}>
                <ul className="space-y-1">
                  {actionItems.map((item, i) => (
                    <li key={i} className="flex items-start gap-2">
                      <span className="text-[10px] font-mono mt-0.5" style={{ color: colors.text.disabled }}>
                        □
                      </span>
                      <span className="text-xs font-mono leading-relaxed" style={{ color: colors.text.secondary }}>
                        {item}
                      </span>
                    </li>
                  ))}
                </ul>
              </Section>
            )}

            {/* Topics */}
            {topics.length > 0 && (
              <Section title="topics" color={colors.accent.purpleSoft}>
                <div className="flex flex-wrap gap-1.5">
                  {topics.map((topic, i) => (
                    <span
                      key={i}
                      className="text-[10px] font-mono px-2 py-0.5 rounded"
                      style={{
                        color: colors.accent.purpleSoft,
                        backgroundColor: `${colors.accent.purpleSoft}1a`
                      }}
                    >
                      {topic}
                    </span>
                  ))}
                </div>
              </Section>
            )}

            {/* MEDDPICC */}
            {insightsMode === 'meddpicc' && (
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
                {meddpiccFields.map((field, i) => (
                  <div
                    key={i}
                    className="rounded p-3 border"
                    style={{
                      borderColor: field.value ? `${field.color}33` : colors.border.primary,
                      backgroundColor: field.value ? `${field.color}0d` : colors.bg.tertiary
                    }}
                  >
                    <div className="flex items-center gap-1.5 mb-1.5">
                      <span
                        className="text-[10px] font-mono font-bold w-4 h-4 flex items-center justify-center rounded"
                        style={{
                          color: field.color,
                          backgroundColor: `${field.color}1a`
                        }}
                      >
                        {field.key}
                      </span>
                      <span className="text-[10px] font-mono font-semibold" style={{ color: field.color }}>
                        {field.label}
                      </span>
                    </div>
                    <p className="text-xs font-mono leading-relaxed" style={{ color: field.value ? colors.text.secondary : colors.text.disabled }}>
                      {field.value || 'No data yet'}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function Section({
  title,
  color,
  children
}: {
  title: string
  color: string
  children: React.ReactNode
}) {
  return (
    <div>
      <div className="flex items-center gap-1.5 mb-2">
        <div className="w-0.5 h-3 rounded-sm" style={{ backgroundColor: color }} />
        <span className="text-[10px] font-mono font-semibold uppercase tracking-wider" style={{ color }}>
          {title}
        </span>
      </div>
      {children}
    </div>
  )
}
