import { useRef, useEffect } from 'react'
import { useStore } from '../store'
import { colors, speakerColor, speakerDisplayName, speakerLabel } from '../colors'
import { MIC_SPEAKER_ID } from '../types'

export function TranscriptView() {
  const liveSegments = useStore((s) => s.liveSegments)
  const interimText = useStore((s) => s.interimText)
  const interimSpeaker = useStore((s) => s.interimSpeaker)
  const currentSpeaker = useStore((s) => s.currentSpeaker)
  const isRecording = useStore((s) => s.isRecording)
  const detectedSpeakers = useStore((s) => s.detectedSpeakers)
  const deepgramApiKey = useStore((s) => s.deepgramApiKey)
  const appMode = useStore((s) => s.appMode)
  const bottomRef = useRef<HTMLDivElement>(null)

  const visibleSegments = liveSegments.filter((s) => s.text.trim().length > 0)
  const hasInterim = interimText.trim().length > 0

  // Auto-scroll to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [visibleSegments.length, interimText])

  // Unique speakers sorted (mic first)
  const speakers = Array.from(
    new Set([...Array.from(detectedSpeakers), ...visibleSegments.map((s) => s.speaker)])
  ).sort((a, b) => {
    if (a === MIC_SPEAKER_ID) return -1
    if (b === MIC_SPEAKER_ID) return 1
    return a - b
  })

  // Empty state
  if (visibleSegments.length === 0 && !hasInterim && !isRecording) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center gap-4">
        <span className="text-5xl" style={{ color: colors.border.primary }}>
          ⬢
        </span>
        <span className="text-sm font-mono" style={{ color: colors.text.meta }}>
          ready to transcribe
        </span>
        {appMode === 'byok' && !deepgramApiKey && (
          <div className="flex flex-col items-center gap-2 mt-2">
            <div className="flex items-center gap-1.5">
              <span style={{ color: colors.accent.orange }}>⚠</span>
              <span className="text-xs font-mono" style={{ color: colors.accent.redGH }}>
                error: deepgram_api_key not set
              </span>
            </div>
            <button
              onClick={() => useStore.setState({ view: 'settings' })}
              className="text-xs font-mono font-semibold px-3 py-1.5 rounded"
              style={{
                color: colors.accent.blueGH,
                backgroundColor: `${colors.accent.blueGH}1a`
              }}
            >
              [ configure ]
            </button>
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full" style={{ backgroundColor: colors.bg.primary }}>
      {/* Speaker legend */}
      {(isRecording || visibleSegments.length > 0) && (
        <div
          className="flex items-center gap-4 px-4 py-2 border-b"
          style={{
            backgroundColor: colors.bg.panel,
            borderColor: colors.border.primary
          }}
        >
          {isRecording && (
            <div className="flex items-center gap-1">
              <div
                className="w-1.5 h-1.5 rounded-full animate-pulse-recording"
                style={{ backgroundColor: colors.status.recording }}
              />
              <span className="text-[10px] font-mono font-semibold" style={{ color: colors.status.recording }}>
                live
              </span>
            </div>
          )}

          <span className="text-[10px] font-mono font-medium" style={{ color: colors.text.subtle }}>
            speakers:
          </span>

          {speakers.length === 0 ? (
            <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
              detecting...
            </span>
          ) : (
            speakers.map((s) => (
              <div key={s} className="flex items-center gap-1">
                <div
                  className="w-1.5 h-1.5 rounded-full"
                  style={{ backgroundColor: speakerColor(s) }}
                />
                <span className="text-[10px] font-mono font-semibold" style={{ color: speakerColor(s) }}>
                  {speakerLabel(s)}
                </span>
              </div>
            ))
          )}
        </div>
      )}

      {/* Transcript */}
      <div className="flex-1 overflow-y-auto px-4 py-3">
        {visibleSegments.map((seg, idx) => {
          const isNewTurn = idx === 0 || seg.speaker !== visibleSegments[idx - 1].speaker
          const color = speakerColor(seg.speaker)

          return (
            <div key={seg.id}>
              {isNewTurn && (
                <div
                  className="flex items-center gap-1.5 mt-3 mb-1"
                  style={{ marginTop: idx === 0 ? 0 : 12 }}
                >
                  <div
                    className="w-0.5 h-3 rounded-sm"
                    style={{ backgroundColor: color }}
                  />
                  <span className="text-[10px] font-mono font-semibold" style={{ color }}>
                    {speakerDisplayName(seg.speaker)}
                  </span>
                  <span className="text-[10px]" style={{ color: colors.border.primary }}>
                    •
                  </span>
                  <span className="text-[10px] font-mono font-medium" style={{ color: colors.text.subtle }}>
                    {formatTimestamp(seg.timestamp)}
                  </span>
                </div>
              )}

              <div className="flex items-start">
                <div
                  className="w-0.5 self-stretch mr-3 rounded-sm"
                  style={{ backgroundColor: `${color}4d` }}
                />
                <p
                  className="text-[13px] font-mono leading-relaxed py-0.5 select-text"
                  style={{ color: colors.text.secondary }}
                >
                  {seg.text}
                </p>
              </div>
            </div>
          )
        })}

        {/* Interim text */}
        {hasInterim && (
          <div>
            {(() => {
              const speaker = interimSpeaker ?? currentSpeaker
              const isNewTurn =
                visibleSegments.length === 0 ||
                visibleSegments[visibleSegments.length - 1].speaker !== speaker
              const color = speakerColor(speaker)

              return (
                <>
                  {isNewTurn && (
                    <div className="flex items-center gap-1.5 mt-3 mb-1">
                      <div
                        className="w-0.5 h-3 rounded-sm"
                        style={{ backgroundColor: `${color}99` }}
                      />
                      <span className="text-[10px] font-mono font-semibold" style={{ color: `${color}b3` }}>
                        {speakerDisplayName(speaker)}
                      </span>
                      <span className="text-[10px]" style={{ color: colors.border.primary }}>
                        •
                      </span>
                      <span className="text-[10px] font-mono" style={{ color: `${colors.accent.greenGH}b3` }}>
                        listening...
                      </span>
                    </div>
                  )}
                  <div className="flex items-start">
                    <div
                      className="w-0.5 self-stretch mr-3 rounded-sm"
                      style={{ backgroundColor: `${color}80` }}
                    />
                    <p className="text-[13px] font-mono leading-relaxed py-0.5">
                      <span style={{ color: colors.text.meta }}>{interimText}</span>
                      <span className="animate-blink" style={{ color }}>
                        ▊
                      </span>
                    </p>
                  </div>
                </>
              )
            })()}
          </div>
        )}

        <div ref={bottomRef} className="h-5" />
      </div>
    </div>
  )
}

function formatTimestamp(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}
