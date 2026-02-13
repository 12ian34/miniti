import { app } from 'electron'
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { join } from 'path'
import { v4 as uuidv4 } from 'uuid'

/**
 * Persistent device UUID stored in app data directory.
 * Survives app reinstalls on Windows (stored in %APPDATA%).
 * Used as the "account" ID for managed mode.
 */

const DEVICE_ID_FILE = 'device-id'

function getDeviceIdPath(): string {
  const dir = join(app.getPath('userData'), '.miniti')
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }
  return join(dir, DEVICE_ID_FILE)
}

export function getOrCreateDeviceId(): string {
  const path = getDeviceIdPath()

  try {
    if (existsSync(path)) {
      const existing = readFileSync(path, 'utf-8').trim()
      if (existing.length > 0) {
        return existing
      }
    }
  } catch {
    // Fall through to create new
  }

  const newId = uuidv4()
  try {
    writeFileSync(path, newId, 'utf-8')
    console.log(`[DeviceIdentifier] Created new device ID: ${newId.substring(0, 8)}...`)
  } catch (err) {
    console.error('[DeviceIdentifier] Failed to save device ID:', err)
  }
  return newId
}

export function existingDeviceId(): string | null {
  try {
    const path = getDeviceIdPath()
    if (existsSync(path)) {
      const existing = readFileSync(path, 'utf-8').trim()
      return existing.length > 0 ? existing : null
    }
  } catch {
    // Ignore
  }
  return null
}
