/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/renderer/src/**/*.{js,ts,jsx,tsx}', './src/renderer/index.html'],
  theme: {
    extend: {
      colors: {
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
        txt: {
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
          'green-gh': '#3FB950',
          blue: '#3B82F6',
          'blue-gh': '#58A6FF',
          purple: '#A855F7',
          'purple-light': '#A78BFA',
          'purple-soft': '#A371F7',
          red: '#EF4444',
          'red-gh': '#F85149',
          amber: '#F59E0B',
          yellow: '#FCE728',
          pink: '#EC4899',
          cyan: '#06B6D4',
          orange: '#D29922'
        }
      },
      fontFamily: {
        mono: [
          'JetBrains Mono',
          'Cascadia Code',
          'Fira Code',
          'Consolas',
          'ui-monospace',
          'monospace'
        ]
      }
    }
  },
  plugins: []
}
