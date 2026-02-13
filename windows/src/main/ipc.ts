import { ipcMain, BrowserWindow } from 'electron'
import { DeepgramService, TranscriptUpdate, ConnectionState, DeepgramModel } from './services/DeepgramService'
import { InsightsService, OpenAIModel, InsightsMode, LiveInsights } from './services/InsightsService'
import { MinitiAPIService } from './services/MinitiAPIService'
import { StorageService, Meeting, TranscriptSegment } from './services/StorageService'
import { getOrCreateDeviceId } from './services/DeviceIdentifier'
import Store from 'electron-store'

// --- Singleton services ---

const deepgram = new DeepgramService()
const insights = new InsightsService()
const api = new MinitiAPIService()
let storage: StorageService | null = null
const settings = new Store({
  defaults: {
    appMode: 'managed',
    hasCompletedOnboarding: false,
    deepgramApiKey: '',
    openaiApiKey: '',
    captureSystemAudio: true,
    captureMicrophone: true,
    deepgramModel: 'nova-3',
    openaiModel: 'gpt-5-mini-2025-08-07',
    insightsMode: 'standard'
  }
})

function getStorage(): StorageService {
  if (!storage) {
    storage = new StorageService()
  }
  return storage
}

function sendToRenderer(channel: string, ...args: unknown[]): void {
  const windows = BrowserWindow.getAllWindows()
  for (const win of windows) {
    win.webContents.send(channel, ...args)
  }
}

// --- Wire up Deepgram events → renderer ---

deepgram.on('transcript', (update: TranscriptUpdate) => {
  sendToRenderer('deepgram:transcript', update)
})

deepgram.on('connectionState', (state: ConnectionState) => {
  sendToRenderer('deepgram:connectionState', state)
})

deepgram.on('error', (err: Error) => {
  sendToRenderer('deepgram:error', err.message)
})

// --- Register all IPC handlers ---

export function registerIpcHandlers(): void {
  // --- Settings ---

  ipcMain.handle('settings:get', (_e, key: string) => {
    return settings.get(key)
  })

  ipcMain.handle('settings:set', (_e, key: string, value: unknown) => {
    settings.set(key, value)
  })

  ipcMain.handle('settings:getAll', () => {
    return settings.store
  })

  // --- Device ID ---

  ipcMain.handle('device:getId', () => {
    return getOrCreateDeviceId()
  })

  // --- Deepgram ---

  ipcMain.handle(
    'deepgram:connect',
    (_e, apiKey: string, model: DeepgramModel) => {
      deepgram.configure(apiKey)
      deepgram.connect(model)
    }
  )

  ipcMain.handle('deepgram:disconnect', () => {
    deepgram.disconnect()
  })

  ipcMain.on('deepgram:sendAudio', (_e, buffer: ArrayBuffer) => {
    deepgram.sendAudio(buffer)
  })

  // --- Insights (BYOK) ---

  ipcMain.handle(
    'insights:generateLive',
    async (
      _e,
      opts: {
        transcript: string
        existingSummary?: string
        existingTitle?: string
        mode?: InsightsMode
        model?: OpenAIModel
        apiKey: string
      }
    ) => {
      return await insights.generateLiveInsights(opts)
    }
  )

  ipcMain.handle(
    'insights:generate',
    async (
      _e,
      opts: {
        transcript: string
        model?: OpenAIModel
        apiKey: string
      }
    ) => {
      return await insights.generateInsights(opts)
    }
  )

  // --- Miniti API (managed mode) ---

  ipcMain.handle('api:checkUsage', async (_e, deviceId: string) => {
    return await api.checkUsage(deviceId)
  })

  ipcMain.handle(
    'api:requestSession',
    async (_e, deviceId: string, model: string) => {
      return await api.requestSession(deviceId, model)
    }
  )

  ipcMain.handle(
    'api:endSession',
    async (_e, deviceId: string, sessionId: string, durationMinutes: number) => {
      return await api.endSession(deviceId, sessionId, durationMinutes)
    }
  )

  ipcMain.handle(
    'api:generateInsights',
    async (
      _e,
      opts: {
        deviceId: string
        transcript: string
        existingSummary?: string
        existingTitle?: string
        mode: string
        model: string
      }
    ) => {
      return await api.generateInsights(opts)
    }
  )

  // --- Storage ---

  ipcMain.handle(
    'storage:saveMeeting',
    (_e, meeting: Meeting, segments: TranscriptSegment[]) => {
      getStorage().saveMeeting(meeting, segments)
    }
  )

  ipcMain.handle('storage:getMeetings', () => {
    return getStorage().getMeetings()
  })

  ipcMain.handle('storage:getMeeting', (_e, id: string) => {
    return getStorage().getMeeting(id)
  })

  ipcMain.handle('storage:deleteMeeting', (_e, id: string) => {
    getStorage().deleteMeeting(id)
  })
}
