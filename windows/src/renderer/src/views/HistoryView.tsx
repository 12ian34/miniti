import { useEffect, useState } from 'react'
import { useStore } from '../store'
import { colors, speakerColor, speakerDisplayName } from '../colors'
import type { Meeting } from '../types'

export function HistoryView() {
  const [meetings, setMeetings] = useState<Meeting[]>([])
  const [loading, setLoading] = useState(true)
  const selectedMeetingId = useStore((s) => s.selectedMeetingId)
  const setSelectedMeetingId = useStore((s) => s.setSelectedMeetingId)
  const [detail, setDetail] = useState<Meeting | null>(null)

  // Load meetings
  useEffect(() => {
    loadMeetings()
  }, [])

  async function loadMeetings() {
    setLoading(true)
    try {
      const list = await window.api.getMeetings()
      setMeetings(list)
    } catch (err) {
      console.error('[History] Failed to load meetings:', err)
    }
    setLoading(false)
  }

  // Load detail when selected
  useEffect(() => {
    if (selectedMeetingId) {
      window.api.getMeeting(selectedMeetingId).then((m) => {
        setDetail(m)
      })
    } else {
      setDetail(null)
    }
  }, [selectedMeetingId])

  async function handleDelete(id: string) {
    if (!confirm('Delete this meeting?')) return
    await window.api.deleteMeeting(id)
    if (selectedMeetingId === id) setSelectedMeetingId(null)
    loadMeetings()
  }

  return (
    <div className="flex h-full">
      {/* Meeting list */}
      <div
        className="w-72 border-r h-full flex flex-col"
        style={{ borderColor: colors.border.primary }}
      >
        <div className="px-4 py-3 border-b" style={{ borderColor: colors.border.primary }}>
          <h2 className="text-sm font-mono font-semibold" style={{ color: colors.text.primary }}>
            meeting history
          </h2>
          <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
            {meetings.length} meetings
          </span>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4">
              <span className="text-xs font-mono" style={{ color: colors.text.subtle }}>
                loading...
              </span>
            </div>
          ) : meetings.length === 0 ? (
            <div className="p-4 text-center">
              <span className="text-xs font-mono" style={{ color: colors.text.subtle }}>
                no meetings yet
              </span>
            </div>
          ) : (
            meetings.map((m) => (
              <button
                key={m.id}
                onClick={() => setSelectedMeetingId(m.id)}
                className="w-full text-left px-4 py-3 border-b transition-colors"
                style={{
                  borderColor: colors.border.primary,
                  backgroundColor: selectedMeetingId === m.id ? colors.bg.tertiary : 'transparent'
                }}
              >
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs font-mono font-semibold truncate" style={{ color: colors.text.primary }}>
                    {m.title}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
                    {formatDate(m.startTime)}
                  </span>
                  {m.endTime && (
                    <span className="text-[10px] font-mono" style={{ color: colors.text.disabled }}>
                      {formatRelativeDuration(m.startTime, m.endTime)}
                    </span>
                  )}
                </div>
                {m.topics && m.topics.length > 0 && (
                  <div className="flex flex-wrap gap-1 mt-1">
                    {m.topics.slice(0, 3).map((t, i) => (
                      <span
                        key={i}
                        className="text-[9px] font-mono px-1 py-px rounded"
                        style={{
                          color: colors.accent.purpleSoft,
                          backgroundColor: `${colors.accent.purpleSoft}1a`
                        }}
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                )}
              </button>
            ))
          )}
        </div>
      </div>

      {/* Meeting detail */}
      <div className="flex-1 overflow-y-auto">
        {detail ? (
          <MeetingDetail meeting={detail} onDelete={() => handleDelete(detail.id)} />
        ) : (
          <div className="flex items-center justify-center h-full">
            <span className="text-sm font-mono" style={{ color: colors.text.subtle }}>
              select a meeting to view details
            </span>
          </div>
        )}
      </div>
    </div>
  )
}

function MeetingDetail({ meeting, onDelete }: { meeting: Meeting; onDelete: () => void }) {
  const [activeSection, setActiveSection] = useState<'transcript' | 'insights' | 'notes'>('transcript')

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="px-6 py-4 border-b" style={{ borderColor: colors.border.primary }}>
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-sm font-mono font-bold" style={{ color: colors.text.primary }}>
            {meeting.title}
          </h2>
          <button
            onClick={onDelete}
            className="text-[10px] font-mono px-2 py-0.5 rounded"
            style={{ color: colors.status.error, backgroundColor: `${colors.status.error}1a` }}
          >
            delete
          </button>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-[10px] font-mono" style={{ color: colors.text.subtle }}>
            {formatDate(meeting.startTime)}
          </span>
          {meeting.endTime && (
            <span className="text-[10px] font-mono" style={{ color: colors.text.disabled }}>
              {formatRelativeDuration(meeting.startTime, meeting.endTime)}
            </span>
          )}
        </div>
      </div>

      {/* Section tabs */}
      <div
        className="flex items-center border-b px-6"
        style={{ borderColor: colors.border.primary }}
      >
        {(['transcript', 'insights', 'notes'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveSection(tab)}
            className="text-xs font-mono font-semibold px-3 py-2 border-b-2 transition-colors"
            style={{
              color: activeSection === tab ? colors.text.primary : colors.text.disabled,
              borderColor: activeSection === tab ? colors.accent.blueGH : 'transparent'
            }}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-4">
        {activeSection === 'transcript' && meeting.segments && (
          <div className="space-y-1">
            {meeting.segments
              .filter((s) => s.isFinal)
              .sort((a, b) => a.timestamp - b.timestamp)
              .map((seg, i, arr) => {
                const isNewTurn = i === 0 || seg.speaker !== arr[i - 1].speaker
                const sColor = speakerColor(seg.speaker)
                return (
                  <div key={seg.id}>
                    {isNewTurn && (
                      <div className="flex items-center gap-1.5 mt-3 mb-1">
                        <div className="w-0.5 h-3 rounded-sm" style={{ backgroundColor: sColor }} />
                        <span className="text-[10px] font-mono font-semibold" style={{ color: sColor }}>
                          {speakerDisplayName(seg.speaker)}
                        </span>
                      </div>
                    )}
                    <div className="flex items-start">
                      <div
                        className="w-0.5 self-stretch mr-3 rounded-sm"
                        style={{ backgroundColor: `${sColor}4d` }}
                      />
                      <p className="text-xs font-mono leading-relaxed py-0.5 select-text" style={{ color: colors.text.secondary }}>
                        {seg.text}
                      </p>
                    </div>
                  </div>
                )
              })}
          </div>
        )}

        {activeSection === 'insights' && (
          <div className="space-y-4">
            {meeting.summaryText && (
              <div>
                <h3 className="text-[10px] font-mono font-semibold uppercase mb-1" style={{ color: colors.accent.blueGH }}>
                  summary
                </h3>
                <p className="text-xs font-mono leading-relaxed" style={{ color: colors.text.secondary }}>
                  {meeting.summaryText}
                </p>
              </div>
            )}
            {meeting.actionItems.length > 0 && (
              <div>
                <h3 className="text-[10px] font-mono font-semibold uppercase mb-1" style={{ color: colors.accent.greenGH }}>
                  action items
                </h3>
                <ul className="space-y-1">
                  {meeting.actionItems.map((item, i) => (
                    <li key={i} className="flex items-start gap-2">
                      <span className="text-[10px] font-mono mt-0.5" style={{ color: colors.text.disabled }}>□</span>
                      <span className="text-xs font-mono" style={{ color: colors.text.secondary }}>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {meeting.topics.length > 0 && (
              <div>
                <h3 className="text-[10px] font-mono font-semibold uppercase mb-1" style={{ color: colors.accent.purpleSoft }}>
                  topics
                </h3>
                <div className="flex flex-wrap gap-1.5">
                  {meeting.topics.map((t, i) => (
                    <span
                      key={i}
                      className="text-[10px] font-mono px-2 py-0.5 rounded"
                      style={{ color: colors.accent.purpleSoft, backgroundColor: `${colors.accent.purpleSoft}1a` }}
                    >
                      {t}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {activeSection === 'notes' && (
          <div>
            {meeting.notes ? (
              <p className="text-xs font-mono leading-relaxed whitespace-pre-wrap" style={{ color: colors.text.secondary }}>
                {meeting.notes}
              </p>
            ) : (
              <p className="text-xs font-mono" style={{ color: colors.text.subtle }}>
                No notes for this meeting.
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  } catch {
    return iso
  }
}

function formatRelativeDuration(start: string, end: string): string {
  try {
    const ms = new Date(end).getTime() - new Date(start).getTime()
    const min = Math.round(ms / 60000)
    if (min >= 60) return `${Math.floor(min / 60)}h ${min % 60}m`
    return `${min}m`
  } catch {
    return ''
  }
}
