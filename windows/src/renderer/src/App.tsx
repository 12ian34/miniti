import { useEffect } from 'react'
import { useStore } from './store'
import { OnboardingView } from './views/OnboardingView'
import { HomeView } from './views/HomeView'
import { RecordingView } from './views/RecordingView'
import { HistoryView } from './views/HistoryView'
import { SettingsView } from './views/SettingsView'
import { Sidebar } from './components/Sidebar'

export default function App() {
  const view = useStore((s) => s.view)
  const hasCompletedOnboarding = useStore((s) => s.hasCompletedOnboarding)
  const loadSettings = useStore((s) => s.loadSettings)
  const handleTranscriptUpdate = useStore((s) => s.handleTranscriptUpdate)
  const refreshUsage = useStore((s) => s.refreshUsage)
  const appMode = useStore((s) => s.appMode)

  // Load settings on mount
  useEffect(() => {
    loadSettings()
  }, [loadSettings])

  // Subscribe to Deepgram events from main process
  useEffect(() => {
    const unsub1 = window.api.onDeepgramTranscript((update) => {
      handleTranscriptUpdate(update as import('./types').TranscriptUpdate)
    })
    const unsub2 = window.api.onDeepgramConnectionState((state) => {
      useStore.setState({ connectionState: state as import('./types').ConnectionState })
    })
    const unsub3 = window.api.onDeepgramError((msg) => {
      console.error('[Deepgram Error]', msg)
    })
    return () => {
      unsub1()
      unsub2()
      unsub3()
    }
  }, [handleTranscriptUpdate])

  // Refresh usage on mode change
  useEffect(() => {
    if (appMode === 'managed' && hasCompletedOnboarding) {
      refreshUsage()
    }
  }, [appMode, hasCompletedOnboarding, refreshUsage])

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Ctrl+, → settings
      if (e.ctrlKey && e.key === ',') {
        e.preventDefault()
        useStore.setState({ view: 'settings' })
      }
      // Ctrl+N → new meeting
      if (e.ctrlKey && e.key === 'n') {
        e.preventDefault()
        useStore.getState().startNewMeeting()
      }
      // Escape → back
      if (e.key === 'Escape') {
        const s = useStore.getState()
        if (s.view === 'settings' || s.view === 'history') {
          useStore.setState({ view: s.hasUnsavedSession ? 'recording' : 'home' })
        }
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  if (!hasCompletedOnboarding) {
    return <OnboardingView />
  }

  // Recording view is full-screen (no sidebar)
  if (view === 'recording') {
    return <RecordingView />
  }

  return (
    <div className="flex h-screen bg-bg-primary">
      {/* Title bar drag region */}
      <div className="titlebar-drag fixed top-0 left-0 right-0 h-9 z-50" />

      <Sidebar />

      <main className="flex-1 pt-9 overflow-hidden">
        <div className="view-enter h-full">
          {view === 'home' && <HomeView />}
          {view === 'history' && <HistoryView />}
          {view === 'settings' && <SettingsView />}
        </div>
      </main>
    </div>
  )
}
