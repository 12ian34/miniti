import { useEffect } from 'react'
import { useStore } from '../store'
import { colors } from '../colors'
import { Waveform } from '../components/Waveform'
import { DEEPGRAM_MODELS, OPENAI_MODELS } from '../types'
import type { DeepgramModel, OpenAIModel } from '../types'

export function HomeView() {
  const appMode = useStore((s) => s.appMode)
  const startNewMeeting = useStore((s) => s.startNewMeeting)
  const deepgramApiKey = useStore((s) => s.deepgramApiKey)
  const openaiApiKey = useStore((s) => s.openaiApiKey)
  const deepgramModel = useStore((s) => s.deepgramModel)
  const openaiModel = useStore((s) => s.openaiModel)
  const saveSetting = useStore((s) => s.saveSetting)
  const captureMicrophone = useStore((s) => s.captureMicrophone)
  const captureSystemAudio = useStore((s) => s.captureSystemAudio)
  const microphoneLevel = useStore((s) => s.microphoneLevel)
  const systemAudioLevel = useStore((s) => s.systemAudioLevel)
  const isMonitoring = useStore((s) => s.isMonitoring)
  const startAudioMonitoring = useStore((s) => s.startAudioMonitoring)
  const stopAudioMonitoring = useStore((s) => s.stopAudioMonitoring)
  const usageInfo = useStore((s) => s.usageInfo)
  const isLoadingUsage = useStore((s) => s.isLoadingUsage)
  const isLimitReached = usageInfo?.isLimitReached ?? false
  const managedSessionError = useStore((s) => s.managedSessionError)

  // Start audio monitoring on mount
  useEffect(() => {
    if (captureMicrophone || captureSystemAudio) {
      startAudioMonitoring()
    }
    return () => stopAudioMonitoring()
  }, [captureMicrophone, captureSystemAudio, startAudioMonitoring, stopAudioMonitoring])

  const canStart =
    appMode === 'managed' ? !isLimitReached : !!deepgramApiKey

  return (
    <div className="h-full flex flex-col items-center justify-center px-8">
      <div className="max-w-md w-full space-y-6">
        {/* Mode status */}
        {appMode === 'managed' ? (
          <div className="text-center">
            {isLoadingUsage ? (
              <span className="text-xs font-mono" style={{ color: colors.text.subtle }}>
                checking usage...
              </span>
            ) : usageInfo ? (
              <div className="space-y-1">
                <span className="text-xs font-mono" style={{ color: colors.text.dim }}>
                  {Math.round(usageInfo.minutesRemaining)}m remaining
                </span>
                <div className="w-48 mx-auto h-1 rounded-full" style={{ backgroundColor: colors.bg.card }}>
                  <div
                    className="h-1 rounded-full transition-all"
                    style={{
                      width: `${Math.min(100, (usageInfo.minutesUsed / usageInfo.minutesLimit) * 100)}%`,
                      backgroundColor: isLimitReached ? colors.status.limitReached : colors.accent.greenGH
                    }}
                  />
                </div>
              </div>
            ) : (
              <span className="text-xs font-mono" style={{ color: colors.accent.greenGH }}>
                early adopter — 500 min/month
              </span>
            )}
          </div>
        ) : (
          <div className="flex items-center justify-center gap-4">
            <ApiPill label="deepgram" hasKey={!!deepgramApiKey} />
            <ApiPill label="openai" hasKey={!!openaiApiKey} />
          </div>
        )}

        {/* Audio sources + waveforms */}
        <div
          className="rounded-lg border p-4 space-y-3"
          style={{ backgroundColor: colors.bg.tertiary, borderColor: colors.border.primary }}
        >
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-mono font-medium" style={{ color: colors.text.subtle }}>
              audio sources
            </span>
            {isMonitoring && (
              <span className="text-[9px] font-mono" style={{ color: colors.accent.greenGH }}>
                monitoring
              </span>
            )}
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={captureMicrophone}
                  onChange={(e) => saveSetting('captureMicrophone', e.target.checked)}
                  className="accent-green-500"
                />
                <span className="text-xs font-mono" style={{ color: colors.text.dim }}>
                  microphone
                </span>
              </label>
              {captureMicrophone && (
                <Waveform level={microphoneLevel} color={colors.accent.greenGH} width={120} height={20} />
              )}
            </div>

            <div className="flex items-center justify-between">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={captureSystemAudio}
                  onChange={(e) => saveSetting('captureSystemAudio', e.target.checked)}
                  className="accent-blue-500"
                />
                <span className="text-xs font-mono" style={{ color: colors.text.dim }}>
                  system audio
                </span>
              </label>
              {captureSystemAudio && (
                <Waveform level={systemAudioLevel} color={colors.accent.blueGH} width={120} height={20} />
              )}
            </div>
          </div>
        </div>

        {/* Model selectors */}
        <div className="flex items-center justify-center gap-4">
          <ModelSelector
            label="transcription"
            value={deepgramModel}
            options={Object.entries(DEEPGRAM_MODELS).map(([k, v]) => ({
              value: k,
              label: `${v.display} (${v.short})`
            }))}
            onChange={(v) => saveSetting('deepgramModel', v)}
          />
          <ModelSelector
            label="insights"
            value={openaiModel}
            options={Object.entries(OPENAI_MODELS).map(([k, v]) => ({
              value: k,
              label: `${v.display} (${v.short})`
            }))}
            onChange={(v) => saveSetting('openaiModel', v)}
          />
        </div>

        {/* Error message */}
        {managedSessionError && (
          <div className="text-center">
            <span className="text-xs font-mono" style={{ color: colors.status.error }}>
              {managedSessionError}
            </span>
          </div>
        )}

        {/* Limit reached */}
        {isLimitReached && (
          <div
            className="rounded-lg border p-4 text-center space-y-2"
            style={{
              borderColor: `${colors.status.limitReached}33`,
              backgroundColor: `${colors.status.limitReached}0d`
            }}
          >
            <p className="text-xs font-mono" style={{ color: colors.status.limitReached }}>
              Monthly limit reached (500 min)
            </p>
            <button
              onClick={() => {
                saveSetting('appMode', 'byok')
                useStore.setState({ appMode: 'byok', view: 'settings' })
              }}
              className="text-xs font-mono font-semibold px-3 py-1 rounded"
              style={{
                color: colors.accent.blueGH,
                backgroundColor: `${colors.accent.blueGH}1a`
              }}
            >
              switch to BYOK
            </button>
          </div>
        )}

        {/* Start button */}
        <div className="flex justify-center">
          <button
            onClick={startNewMeeting}
            disabled={!canStart}
            className="text-sm font-mono font-bold px-8 py-3 rounded-lg transition-all"
            style={{
              color: canStart ? colors.bg.primary : colors.text.disabled,
              backgroundColor: canStart ? colors.accent.greenGH : colors.bg.card,
              opacity: canStart ? 1 : 0.5
            }}
          >
            [ start recording ]
          </button>
        </div>

        {/* Keyboard shortcut hint */}
        <p className="text-center text-[10px] font-mono" style={{ color: colors.text.placeholder }}>
          Ctrl+N to start • Ctrl+, for settings
        </p>
      </div>
    </div>
  )
}

function ApiPill({ label, hasKey }: { label: string; hasKey: boolean }) {
  return (
    <button
      onClick={() => useStore.setState({ view: 'settings' })}
      className="flex items-center gap-1.5 px-2.5 py-1 rounded text-[10px] font-mono transition-colors"
      style={{
        backgroundColor: colors.bg.card,
        borderColor: colors.border.primary,
        border: '1px solid'
      }}
    >
      <div
        className="w-1.5 h-1.5 rounded-full"
        style={{
          backgroundColor: hasKey ? colors.status.connected : colors.status.noApiKey
        }}
      />
      <span style={{ color: hasKey ? colors.text.dim : colors.status.noApiKey }}>{label}</span>
    </button>
  )
}

function ModelSelector({
  label,
  value,
  options,
  onChange
}: {
  label: string
  value: string
  options: Array<{ value: string; label: string }>
  onChange: (value: string) => void
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
        {label}:
      </span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="text-[10px] font-mono bg-transparent border rounded px-1.5 py-0.5 cursor-pointer"
        style={{
          color: colors.text.dim,
          borderColor: colors.border.primary,
          backgroundColor: colors.bg.card
        }}
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  )
}
