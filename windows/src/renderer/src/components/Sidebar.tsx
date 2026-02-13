import { useStore } from '../store'
import { colors } from '../colors'
import type { AppView } from '../types'

export function Sidebar() {
  const view = useStore((s) => s.view)
  const setView = useStore((s) => s.setView)
  const hasUnsavedSession = useStore((s) => s.hasUnsavedSession)

  const navItems: Array<{ id: AppView; label: string; shortcut: string }> = [
    { id: 'home', label: 'rec', shortcut: 'Ctrl+N' },
    { id: 'history', label: 'history', shortcut: 'Ctrl+H' },
    { id: 'settings', label: 'settings', shortcut: 'Ctrl+,' }
  ]

  return (
    <aside
      className="w-48 h-full flex flex-col border-r pt-9"
      style={{
        backgroundColor: colors.bg.secondary,
        borderColor: colors.border.primary
      }}
    >
      {/* Logo */}
      <div className="px-4 py-4 border-b" style={{ borderColor: colors.border.primary }}>
        <div className="flex items-center gap-2">
          <div
            className="w-2 h-2 rounded-full"
            style={{ backgroundColor: colors.accent.greenGH }}
          />
          <span
            className="text-sm font-semibold font-mono"
            style={{ color: colors.text.primary }}
          >
            miniti
          </span>
          <span
            className="text-[10px] font-mono"
            style={{ color: colors.text.subtle }}
          >
            win
          </span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-2 py-3 space-y-0.5">
        {navItems.map((item) => {
          const isActive = view === item.id || (item.id === 'home' && view === 'recording')
          return (
            <button
              key={item.id}
              onClick={() => {
                if (item.id === 'home' && hasUnsavedSession) {
                  setView('recording')
                } else {
                  setView(item.id)
                }
              }}
              className="w-full text-left px-3 py-1.5 rounded text-xs font-mono flex items-center justify-between transition-colors"
              style={{
                backgroundColor: isActive ? colors.bg.tertiary : 'transparent',
                color: isActive ? colors.text.primary : colors.text.dim
              }}
            >
              <span>{hasUnsavedSession && item.id === 'home' ? 'session' : item.label}</span>
              <span
                className="text-[9px]"
                style={{ color: colors.text.placeholder }}
              >
                {item.shortcut}
              </span>
            </button>
          )
        })}
      </nav>

      {/* Status */}
      <div className="px-4 py-3 border-t" style={{ borderColor: colors.border.primary }}>
        <div className="flex items-center gap-2">
          <div
            className="w-1.5 h-1.5 rounded-full"
            style={{ backgroundColor: colors.status.connected }}
          />
          <span
            className="text-[10px] font-mono"
            style={{ color: colors.text.subtle }}
          >
            ready
          </span>
        </div>
      </div>
    </aside>
  )
}
