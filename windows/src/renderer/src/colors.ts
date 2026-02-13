/**
 * Color palette — matches the macOS ColorPalette.swift exactly.
 * Used for inline styles when Tailwind classes aren't sufficient.
 */

export const colors = {
  bg: {
    primary: '#09090B',
    secondary: '#0C0C0E',
    tertiary: '#111113',
    panel: '#0F0F11',
    card: '#18181B'
  },
  border: {
    primary: '#1C1C1F',
    light: '#27272A',
    hover: '#3F3F46',
    subtle: '#30363D'
  },
  text: {
    primary: '#FAFAFA',
    secondary: '#E6EDF3',
    muted: '#D4D4D8',
    dim: '#A1A1AA',
    disabled: '#71717A',
    placeholder: '#52525B',
    subtle: '#484F58',
    meta: '#8B949E'
  },
  accent: {
    green: '#22C55E',
    greenGH: '#3FB950',
    blue: '#3B82F6',
    blueGH: '#58A6FF',
    purple: '#A855F7',
    purpleLight: '#A78BFA',
    purpleSoft: '#A371F7',
    red: '#EF4444',
    redGH: '#F85149',
    amber: '#F59E0B',
    yellow: '#FCE728',
    pink: '#EC4899',
    cyan: '#06B6D4',
    orange: '#D29922'
  },
  status: {
    success: '#3FB950',
    error: '#F85149',
    warning: '#F59E0B',
    info: '#58A6FF',
    recording: '#F85149',
    connected: '#3FB950',
    disconnected: '#71717A',
    limitReached: '#F85149',
    noApiKey: '#F59E0B'
  },
  speaker: {
    mic: '#3FB950',
    remote: ['#58A6FF', '#A371F7', '#D29922', '#F778BA', '#79C0FF', '#FFA657', '#7EE787']
  },
  meddpicc: {
    M: '#3B82F6',
    E: '#8B5CF6',
    D: '#EC4899',
    P: '#F59E0B',
    I: '#EF4444',
    C: '#22C55E'
  }
} as const

export function speakerColor(speaker: number): string {
  if (speaker === 1000) return colors.speaker.mic
  return colors.speaker.remote[speaker % colors.speaker.remote.length]
}

export function speakerLabel(speaker: number): string {
  if (speaker === 1000) return 'You'
  return `S${speaker + 1}`
}

export function speakerDisplayName(speaker: number): string {
  if (speaker === 1000) return 'You'
  return `Speaker ${speaker + 1}`
}
