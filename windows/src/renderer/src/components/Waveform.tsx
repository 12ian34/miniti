import { useRef, useEffect } from 'react'

interface WaveformProps {
  level: number
  color: string
  label?: string
  width?: number
  height?: number
}

export function Waveform({ level, color, label, width = 200, height = 32 }: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const historyRef = useRef<number[]>([])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Push new level using power curve (same as macOS: pow(level, 0.2))
    const displayLevel = Math.pow(Math.max(0, Math.min(1, level * 10)), 0.2)
    historyRef.current.push(displayLevel)
    if (historyRef.current.length > width / 2) {
      historyRef.current.shift()
    }

    // Draw
    ctx.clearRect(0, 0, width, height)

    const barWidth = 2
    const gap = 1
    const bars = historyRef.current
    const startX = width - bars.length * (barWidth + gap)

    for (let i = 0; i < bars.length; i++) {
      const barHeight = Math.max(1, bars[i] * (height - 4))
      const x = startX + i * (barWidth + gap)
      const y = (height - barHeight) / 2

      ctx.fillStyle = color
      ctx.globalAlpha = 0.3 + bars[i] * 0.7
      ctx.fillRect(x, y, barWidth, barHeight)
    }

    ctx.globalAlpha = 1
  }, [level, color, width, height])

  return (
    <div className="flex items-center gap-2">
      {label && (
        <span
          className="text-[10px] font-mono font-medium w-10"
          style={{ color }}
        >
          {label}
        </span>
      )}
      <canvas
        ref={canvasRef}
        width={width}
        height={height}
        className="block"
        style={{ width, height }}
      />
    </div>
  )
}
