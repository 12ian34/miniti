import { useStore } from '../store'
import { colors } from '../colors'
import { Waveform } from '../components/Waveform'
import { TranscriptView } from '../components/TranscriptView'
import { InsightsView } from '../components/InsightsView'

export function RecordingView() {
  const isRecording = useStore((s) => s.isRecording)
  const recordingDuration = useStore((s) => s.recordingDuration)
  const currentMeetingTitle = useStore((s) => s.currentMeetingTitle)
  const stopRecording = useStore((s) => s.stopRecording)
  const resumeRecording = useStore((s) => s.resumeRecording)
  const goHome = useStore((s) => s.goHome)
  const microphoneLevel = useStore((s) => s.microphoneLevel)
  const systemAudioLevel = useStore((s) => s.systemAudioLevel)
  const captureMicrophone = useStore((s) => s.captureMicrophone)
  const captureSystemAudio = useStore((s) => s.captureSystemAudio)
  const selectedTab = useStore((s) => s.selectedTab)
  const setSelectedTab = useStore((s) => s.setSelectedTab)
  const liveNotes = useStore((s) => s.liveNotes)
  const setLiveNotes = useStore((s) => s.setLiveNotes)
  const liveSegments = useStore((s) => s.liveSegments)
  const connectionState = useStore((s) => s.connectionState)

  const formattedDuration = formatDuration(recordingDuration)
  const hasContent = liveSegments.filter((s) => s.isFinal && s.text.trim()).length > 0

  return (
    <div className="flex flex-col h-screen" style={{ backgroundColor: colors.bg.primary }}>
      {/* Title bar drag region */}
      <div className="titlebar-drag fixed top-0 left-0 right-0 h-9 z-50" />

      {/* Header */}
      <div
        className="titlebar-no-drag flex items-center justify-between px-4 py-2 border-b mt-9"
        style={{ backgroundColor: colors.bg.secondary, borderColor: colors.border.primary }}
      >
        <div className="flex items-center gap-3">
          {/* Recording status */}
          {isRecording ? (
            <div className="flex items-center gap-1.5">
              <div
                className="w-2 h-2 rounded-full animate-pulse-recording"
                style={{ backgroundColor: colors.status.recording }}
              />
              <span className="text-xs font-mono font-bold" style={{ color: colors.status.recording }}>
                REC
              </span>
            </div>
          ) : (
            <div className="flex items-center gap-1.5">
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: colors.text.disabled }}
              />
              <span className="text-xs font-mono font-bold" style={{ color: colors.text.disabled }}>
                PAUSED
              </span>
            </div>
          )}

          {/* Timer */}
          <span className="text-sm font-mono font-bold tabular-nums" style={{ color: colors.text.primary }}>
            {formattedDuration}
          </span>

          {/* Title */}
          <span className="text-xs font-mono" style={{ color: colors.text.subtle }}>
            {currentMeetingTitle}
          </span>

          {/* Connection state */}
          {connectionState === 'connecting' && (
            <span className="text-[10px] font-mono" style={{ color: colors.accent.amber }}>
              connecting...
            </span>
          )}
        </div>

        {/* Controls */}
        <div className="flex items-center gap-2">
          {isRecording ? (
            <button
              onClick={stopRecording}
              className="text-xs font-mono font-bold px-4 py-1.5 rounded transition-colors"
              style={{
                color: colors.status.recording,
                backgroundColor: `${colors.status.recording}1a`
              }}
            >
              [ stop ]
            </button>
          ) : (
            <>
              <button
                onClick={goHome}
                className="text-xs font-mono font-bold px-3 py-1.5 rounded transition-colors"
                style={{
                  color: colors.text.dim,
                  backgroundColor: colors.bg.card
                }}
              >
                [ home ]
              </button>
              <button
                onClick={resumeRecording}
                className="text-xs font-mono font-bold px-4 py-1.5 rounded transition-colors"
                style={{
                  color: colors.accent.greenGH,
                  backgroundColor: `${colors.accent.greenGH}1a`
                }}
              >
                [ cont ]
              </button>
              {hasContent && (
                <button
                  onClick={goHome}
                  className="text-xs font-mono font-bold px-3 py-1.5 rounded transition-colors"
                  style={{
                    color: colors.accent.blueGH,
                    backgroundColor: `${colors.accent.blueGH}1a`
                  }}
                >
                  [ save ]
                </button>
              )}
            </>
          )}
        </div>
      </div>

      {/* Waveforms */}
      <div
        className="flex items-center gap-4 px-4 py-1.5 border-b"
        style={{ backgroundColor: colors.bg.panel, borderColor: colors.border.primary }}
      >
        {captureMicrophone && (
          <Waveform level={microphoneLevel} color={colors.accent.greenGH} label="mic" width={150} height={18} />
        )}
        {captureSystemAudio && (
          <Waveform level={systemAudioLevel} color={colors.accent.blueGH} label="sys" width={150} height={18} />
        )}
      </div>

      {/* Tab selector */}
      <div
        className="flex items-center border-b px-4"
        style={{ backgroundColor: colors.bg.secondary, borderColor: colors.border.primary }}
      >
        {(['transcript', 'insights'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setSelectedTab(tab)}
            className="text-xs font-mono font-semibold px-4 py-2 border-b-2 transition-colors"
            style={{
              color: selectedTab === tab ? colors.text.primary : colors.text.disabled,
              borderColor: selectedTab === tab ? colors.accent.blueGH : 'transparent'
            }}
          >
            {tab}
          </button>
        ))}

        {/* Notes toggle (always visible) */}
        <div className="ml-auto flex items-center">
          <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
            notes
          </span>
        </div>
      </div>

      {/* Content area */}
      <div className="flex flex-1 overflow-hidden">
        {/* Main content */}
        <div className="flex-1 overflow-hidden">
          {selectedTab === 'transcript' ? <TranscriptView /> : <InsightsView />}
        </div>

        {/* Notes panel */}
        <div
          className="w-64 border-l flex flex-col"
          style={{
            backgroundColor: colors.bg.secondary,
            borderColor: colors.border.primary
          }}
        >
          <div className="px-3 py-2 border-b" style={{ borderColor: colors.border.primary }}>
            <span className="text-[10px] font-mono font-medium" style={{ color: colors.text.subtle }}>
              notes
            </span>
          </div>
          <textarea
            value={liveNotes}
            onChange={(e) => setLiveNotes(e.target.value)}
            placeholder="Type your notes here..."
            className="flex-1 resize-none p-3 text-xs font-mono leading-relaxed focus:outline-none"
            style={{
              backgroundColor: 'transparent',
              color: colors.text.secondary,
              caretColor: colors.accent.greenGH
            }}
          />
        </div>
      </div>
    </div>
  )
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60)
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
}
