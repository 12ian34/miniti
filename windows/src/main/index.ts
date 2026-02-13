import { app, BrowserWindow, shell, desktopCapturer } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'
import { registerIpcHandlers } from './ipc'

let mainWindow: BrowserWindow | null = null

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    show: false,
    backgroundColor: '#09090B',
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#09090B',
      symbolColor: '#A1A1AA',
      height: 36
    },
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  mainWindow.on('ready-to-show', () => {
    mainWindow?.show()
  })

  // Open external links in default browser
  mainWindow.webContents.setWindowOpenHandler((details) => {
    shell.openExternal(details.url)
    return { action: 'deny' }
  })

  // Load the renderer
  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

// Allow desktopCapturer for system audio
app.commandLine.appendSwitch('enable-features', 'DesktopCaptureAudio')

app.whenReady().then(() => {
  // Register IPC handlers for renderer communication
  registerIpcHandlers()

  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  app.quit()
})

// Expose desktopCapturer to renderer via IPC (needed for system audio capture)
import { ipcMain } from 'electron'

ipcMain.handle('get-desktop-sources', async () => {
  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    fetchWindowIcons: false
  })
  // Return serializable data (DesktopCapturerSource has non-serializable fields)
  return sources.map((s) => ({
    id: s.id,
    name: s.name,
    display_id: s.display_id
  }))
})
