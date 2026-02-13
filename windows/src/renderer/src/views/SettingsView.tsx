import { useState, useEffect } from 'react'
import { useStore } from '../store'
import { colors } from '../colors'
import { DEEPGRAM_MODELS, OPENAI_MODELS } from '../types'
import type { AppMode, DeepgramModel, OpenAIModel } from '../types'

export function SettingsView() {
  const appMode = useStore((s) => s.appMode)
  const deepgramApiKey = useStore((s) => s.deepgramApiKey)
  const openaiApiKey = useStore((s) => s.openaiApiKey)
  const deepgramModel = useStore((s) => s.deepgramModel)
  const openaiModel = useStore((s) => s.openaiModel)
  const captureMicrophone = useStore((s) => s.captureMicrophone)
  const captureSystemAudio = useStore((s) => s.captureSystemAudio)
  const usageInfo = useStore((s) => s.usageInfo)
  const saveSetting = useStore((s) => s.saveSetting)
  const refreshUsage = useStore((s) => s.refreshUsage)

  const [deviceId, setDeviceId] = useState('')
  const [activeTab, setActiveTab] = useState<'account' | 'api' | 'audio' | 'general'>('account')

  useEffect(() => {
    window.api.getDeviceId().then(setDeviceId)
  }, [])

  const tabs = [
    { id: 'account' as const, label: 'Account' },
    { id: 'api' as const, label: 'API Keys' },
    { id: 'audio' as const, label: 'Audio' },
    { id: 'general' as const, label: 'General' }
  ]

  return (
    <div className="h-full flex flex-col">
      <div className="px-6 py-4 border-b" style={{ borderColor: colors.border.primary }}>
        <h1 className="text-sm font-mono font-bold" style={{ color: colors.text.primary }}>
          settings
        </h1>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* Tab sidebar */}
        <div className="w-40 border-r py-2" style={{ borderColor: colors.border.primary }}>
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className="w-full text-left px-4 py-1.5 text-xs font-mono transition-colors"
              style={{
                color: activeTab === tab.id ? colors.text.primary : colors.text.dim,
                backgroundColor: activeTab === tab.id ? colors.bg.tertiary : 'transparent'
              }}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {activeTab === 'account' && (
            <>
              {/* Mode toggle */}
              <SettingsSection title="App Mode">
                <div className="space-y-2">
                  {([
                    { mode: 'managed' as AppMode, label: 'Early Adopter', desc: '500 free min/month' },
                    { mode: 'byok' as AppMode, label: 'Bring Your Own Keys', desc: 'Unlimited, your API keys' }
                  ]).map(({ mode, label, desc }) => (
                    <label
                      key={mode}
                      className="flex items-center gap-3 p-3 rounded border cursor-pointer transition-colors"
                      style={{
                        borderColor: appMode === mode ? colors.accent.greenGH + '33' : colors.border.primary,
                        backgroundColor: appMode === mode ? colors.accent.greenGH + '0d' : colors.bg.tertiary
                      }}
                    >
                      <input
                        type="radio"
                        name="appMode"
                        checked={appMode === mode}
                        onChange={() => {
                          saveSetting('appMode', mode)
                          if (mode === 'managed') refreshUsage()
                        }}
                        className="accent-green-500"
                      />
                      <div>
                        <span className="text-xs font-mono font-semibold" style={{ color: colors.text.primary }}>
                          {label}
                        </span>
                        <p className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
                          {desc}
                        </p>
                      </div>
                    </label>
                  ))}
                </div>
              </SettingsSection>

              {/* Usage stats (managed) */}
              {appMode === 'managed' && usageInfo && (
                <SettingsSection title="Usage">
                  <div className="space-y-2">
                    <div className="flex justify-between text-xs font-mono">
                      <span style={{ color: colors.text.dim }}>Used</span>
                      <span style={{ color: colors.text.primary }}>
                        {Math.round(usageInfo.minutesUsed)} / {usageInfo.minutesLimit} min
                      </span>
                    </div>
                    <div className="w-full h-1.5 rounded-full" style={{ backgroundColor: colors.bg.card }}>
                      <div
                        className="h-1.5 rounded-full transition-all"
                        style={{
                          width: `${Math.min(100, (usageInfo.minutesUsed / usageInfo.minutesLimit) * 100)}%`,
                          backgroundColor: usageInfo.isLimitReached ? colors.status.limitReached : colors.accent.greenGH
                        }}
                      />
                    </div>
                    <div className="flex justify-between text-[10px] font-mono">
                      <span style={{ color: colors.text.subtle }}>
                        {Math.round(usageInfo.minutesRemaining)}m remaining
                      </span>
                      <span style={{ color: colors.text.subtle }}>
                        Resets: {new Date(usageInfo.resetsAt).toLocaleDateString()}
                      </span>
                    </div>
                  </div>
                </SettingsSection>
              )}

              {/* Device ID */}
              <SettingsSection title="Device ID">
                <div
                  className="text-[10px] font-mono p-2 rounded border select-all"
                  style={{
                    color: colors.text.dim,
                    backgroundColor: colors.bg.tertiary,
                    borderColor: colors.border.primary
                  }}
                >
                  {deviceId}
                </div>
              </SettingsSection>
            </>
          )}

          {activeTab === 'api' && (
            <>
              {appMode === 'managed' ? (
                <div className="p-4 rounded border" style={{ borderColor: colors.border.primary, backgroundColor: colors.bg.tertiary }}>
                  <p className="text-xs font-mono" style={{ color: colors.text.meta }}>
                    API keys are managed automatically in Early Adopter mode.
                    Switch to BYOK mode to use your own keys.
                  </p>
                </div>
              ) : (
                <>
                  <SettingsSection title="Deepgram API Key">
                    <input
                      type="password"
                      value={deepgramApiKey}
                      onChange={(e) => saveSetting('deepgramApiKey', e.target.value)}
                      placeholder="Enter your Deepgram API key..."
                      className="w-full text-xs font-mono p-2 rounded border focus:outline-none"
                      style={{
                        color: colors.text.primary,
                        backgroundColor: colors.bg.tertiary,
                        borderColor: colors.border.primary,
                        caretColor: colors.accent.greenGH
                      }}
                    />
                    <p className="text-[10px] font-mono mt-1" style={{ color: colors.text.subtle }}>
                      Get one at{' '}
                      <a href="https://console.deepgram.com" className="underline" style={{ color: colors.accent.blueGH }}>
                        console.deepgram.com
                      </a>
                    </p>
                  </SettingsSection>

                  <SettingsSection title="OpenAI API Key">
                    <input
                      type="password"
                      value={openaiApiKey}
                      onChange={(e) => saveSetting('openaiApiKey', e.target.value)}
                      placeholder="Enter your OpenAI API key..."
                      className="w-full text-xs font-mono p-2 rounded border focus:outline-none"
                      style={{
                        color: colors.text.primary,
                        backgroundColor: colors.bg.tertiary,
                        borderColor: colors.border.primary,
                        caretColor: colors.accent.greenGH
                      }}
                    />
                    <p className="text-[10px] font-mono mt-1" style={{ color: colors.text.subtle }}>
                      Get one at{' '}
                      <a href="https://platform.openai.com/api-keys" className="underline" style={{ color: colors.accent.blueGH }}>
                        platform.openai.com
                      </a>
                    </p>
                  </SettingsSection>
                </>
              )}
            </>
          )}

          {activeTab === 'audio' && (
            <>
              <SettingsSection title="Audio Sources">
                <div className="space-y-3">
                  <label className="flex items-center gap-3 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={captureMicrophone}
                      onChange={(e) => saveSetting('captureMicrophone', e.target.checked)}
                      className="accent-green-500"
                    />
                    <div>
                      <span className="text-xs font-mono" style={{ color: colors.text.primary }}>
                        Microphone
                      </span>
                      <p className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
                        Capture from your mic (your voice)
                      </p>
                    </div>
                  </label>

                  <label className="flex items-center gap-3 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={captureSystemAudio}
                      onChange={(e) => saveSetting('captureSystemAudio', e.target.checked)}
                      className="accent-blue-500"
                    />
                    <div>
                      <span className="text-xs font-mono" style={{ color: colors.text.primary }}>
                        System Audio
                      </span>
                      <p className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
                        Capture audio from other apps (Zoom, Teams, etc.)
                      </p>
                    </div>
                  </label>
                </div>
              </SettingsSection>

              <SettingsSection title="Transcription Model">
                <div className="space-y-2">
                  {(Object.entries(DEEPGRAM_MODELS) as [DeepgramModel, { display: string; short: string }][]).map(
                    ([value, info]) => (
                      <label
                        key={value}
                        className="flex items-center gap-3 p-2 rounded border cursor-pointer transition-colors"
                        style={{
                          borderColor: deepgramModel === value ? colors.accent.blueGH + '33' : colors.border.primary,
                          backgroundColor: deepgramModel === value ? colors.accent.blueGH + '0d' : 'transparent'
                        }}
                      >
                        <input
                          type="radio"
                          name="deepgramModel"
                          checked={deepgramModel === value}
                          onChange={() => saveSetting('deepgramModel', value)}
                          className="accent-blue-500"
                        />
                        <span className="text-xs font-mono" style={{ color: colors.text.primary }}>
                          {info.display}{' '}
                          <span style={{ color: colors.text.subtle }}>({info.short})</span>
                        </span>
                      </label>
                    )
                  )}
                </div>
              </SettingsSection>
            </>
          )}

          {activeTab === 'general' && (
            <>
              <SettingsSection title="Insights Model">
                <div className="space-y-2">
                  {(Object.entries(OPENAI_MODELS) as [OpenAIModel, { display: string; short: string }][]).map(
                    ([value, info]) => (
                      <label
                        key={value}
                        className="flex items-center gap-3 p-2 rounded border cursor-pointer transition-colors"
                        style={{
                          borderColor: openaiModel === value ? colors.accent.blueGH + '33' : colors.border.primary,
                          backgroundColor: openaiModel === value ? colors.accent.blueGH + '0d' : 'transparent'
                        }}
                      >
                        <input
                          type="radio"
                          name="openaiModel"
                          checked={openaiModel === value}
                          onChange={() => saveSetting('openaiModel', value)}
                          className="accent-blue-500"
                        />
                        <span className="text-xs font-mono" style={{ color: colors.text.primary }}>
                          {info.display}{' '}
                          <span style={{ color: colors.text.subtle }}>({info.short})</span>
                        </span>
                      </label>
                    )
                  )}
                </div>
              </SettingsSection>

              <SettingsSection title="About">
                <div className="space-y-1">
                  <p className="text-xs font-mono" style={{ color: colors.text.dim }}>
                    miniti for Windows v1.4.0
                  </p>
                  <p className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
                    Built with Electron + React + TypeScript
                  </p>
                </div>
              </SettingsSection>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-mono font-semibold mb-2" style={{ color: colors.text.muted }}>
        {title}
      </h3>
      {children}
    </div>
  )
}
