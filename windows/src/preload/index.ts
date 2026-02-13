import { contextBridge, ipcRenderer } from 'electron'

/**
 * Exposes a safe API to the renderer process via window.api.
 * All communication between renderer and main goes through these channels.
 */

const api = {
  // --- Settings ---
  getSetting: (key: string) => ipcRenderer.invoke('settings:get', key),
  setSetting: (key: string, value: unknown) => ipcRenderer.invoke('settings:set', key, value),
  getAllSettings: () => ipcRenderer.invoke('settings:getAll'),

  // --- Device ---
  getDeviceId: () => ipcRenderer.invoke('device:getId'),

  // --- Desktop Capturer (system audio) ---
  getDesktopSources: () => ipcRenderer.invoke('get-desktop-sources'),

  // --- Deepgram ---
  deepgramConnect: (apiKey: string, model: string) =>
    ipcRenderer.invoke('deepgram:connect', apiKey, model),
  deepgramDisconnect: () => ipcRenderer.invoke('deepgram:disconnect'),
  deepgramSendAudio: (buffer: ArrayBuffer) =>
    ipcRenderer.send('deepgram:sendAudio', buffer),

  onDeepgramTranscript: (cb: (update: unknown) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, update: unknown) => cb(update)
    ipcRenderer.on('deepgram:transcript', handler)
    return () => ipcRenderer.removeListener('deepgram:transcript', handler)
  },
  onDeepgramConnectionState: (cb: (state: string) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, state: string) => cb(state)
    ipcRenderer.on('deepgram:connectionState', handler)
    return () => ipcRenderer.removeListener('deepgram:connectionState', handler)
  },
  onDeepgramError: (cb: (msg: string) => void) => {
    const handler = (_e: Electron.IpcRendererEvent, msg: string) => cb(msg)
    ipcRenderer.on('deepgram:error', handler)
    return () => ipcRenderer.removeListener('deepgram:error', handler)
  },

  // --- Insights (BYOK) ---
  generateLiveInsights: (opts: unknown) => ipcRenderer.invoke('insights:generateLive', opts),
  generateInsights: (opts: unknown) => ipcRenderer.invoke('insights:generate', opts),

  // --- Miniti API (managed) ---
  checkUsage: (deviceId: string) => ipcRenderer.invoke('api:checkUsage', deviceId),
  requestSession: (deviceId: string, model: string) =>
    ipcRenderer.invoke('api:requestSession', deviceId, model),
  endSession: (deviceId: string, sessionId: string, durationMinutes: number) =>
    ipcRenderer.invoke('api:endSession', deviceId, sessionId, durationMinutes),
  apiGenerateInsights: (opts: unknown) => ipcRenderer.invoke('api:generateInsights', opts),

  // --- Storage ---
  saveMeeting: (meeting: unknown, segments: unknown[]) =>
    ipcRenderer.invoke('storage:saveMeeting', meeting, segments),
  getMeetings: () => ipcRenderer.invoke('storage:getMeetings'),
  getMeeting: (id: string) => ipcRenderer.invoke('storage:getMeeting', id),
  deleteMeeting: (id: string) => ipcRenderer.invoke('storage:deleteMeeting', id)
}

contextBridge.exposeInMainWorld('api', api)

export type API = typeof api
