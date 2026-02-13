import { useStore } from '../store'
import { colors } from '../colors'

export function OnboardingView() {
  const completeOnboarding = useStore((s) => s.completeOnboarding)

  return (
    <div
      className="h-screen flex flex-col items-center justify-center"
      style={{ backgroundColor: colors.bg.primary }}
    >
      {/* Title bar drag region */}
      <div className="titlebar-drag fixed top-0 left-0 right-0 h-9" />

      <div className="max-w-lg w-full px-8">
        {/* Logo */}
        <div className="flex items-center gap-3 mb-8">
          <div className="w-3 h-3 rounded-full" style={{ backgroundColor: colors.accent.greenGH }} />
          <h1 className="text-2xl font-mono font-bold" style={{ color: colors.text.primary }}>
            miniti
          </h1>
        </div>

        <p className="text-sm font-mono mb-8" style={{ color: colors.text.meta }}>
          AI meeting assistant for Windows. Record mic + system audio, get live transcription with
          speaker identification, and AI-generated insights.
        </p>

        <p className="text-xs font-mono mb-6" style={{ color: colors.text.dim }}>
          Choose how you'd like to use miniti:
        </p>

        {/* Mode cards */}
        <div className="space-y-3">
          <ModeCard
            title="Early Adopter"
            tag="recommended"
            tagColor={colors.accent.greenGH}
            description="500 free minutes/month. No API keys needed. We handle everything."
            features={['No setup required', '500 min/month free', 'Automatic updates']}
            onClick={() => completeOnboarding('managed')}
            buttonLabel="[ get started ]"
            buttonColor={colors.accent.greenGH}
          />

          <ModeCard
            title="Bring Your Own Keys"
            tag="advanced"
            tagColor={colors.accent.blueGH}
            description="Use your own Deepgram + OpenAI API keys. Unlimited usage, you control costs."
            features={['Unlimited usage', 'Your own API keys', 'Full control']}
            onClick={() => completeOnboarding('byok')}
            buttonLabel="[ configure ]"
            buttonColor={colors.accent.blueGH}
          />
        </div>
      </div>
    </div>
  )
}

function ModeCard({
  title,
  tag,
  tagColor,
  description,
  features,
  onClick,
  buttonLabel,
  buttonColor
}: {
  title: string
  tag: string
  tagColor: string
  description: string
  features: string[]
  onClick: () => void
  buttonLabel: string
  buttonColor: string
}) {
  return (
    <div
      className="rounded-lg border p-4 transition-colors cursor-pointer hover:border-opacity-60"
      style={{
        backgroundColor: colors.bg.tertiary,
        borderColor: colors.border.primary
      }}
      onClick={onClick}
    >
      <div className="flex items-center gap-2 mb-2">
        <span className="text-sm font-mono font-semibold" style={{ color: colors.text.primary }}>
          {title}
        </span>
        <span
          className="text-[9px] font-mono px-1.5 py-0.5 rounded"
          style={{ color: tagColor, backgroundColor: `${tagColor}1a` }}
        >
          {tag}
        </span>
      </div>

      <p className="text-xs font-mono mb-3" style={{ color: colors.text.meta }}>
        {description}
      </p>

      <div className="flex items-center gap-4 mb-3">
        {features.map((f, i) => (
          <div key={i} className="flex items-center gap-1">
            <span style={{ color: tagColor }}>✓</span>
            <span className="text-[10px] font-mono" style={{ color: colors.text.dim }}>
              {f}
            </span>
          </div>
        ))}
      </div>

      <button
        className="text-xs font-mono font-semibold px-4 py-1.5 rounded transition-colors"
        style={{
          color: buttonColor,
          backgroundColor: `${buttonColor}1a`
        }}
      >
        {buttonLabel}
      </button>
    </div>
  )
}
