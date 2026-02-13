# miniti for Windows

Electron + React + TypeScript port of the miniti AI meeting assistant.

## Setup

```bash
cd windows
npm install
npm run dev
```

## Build

```bash
npm run package        # NSIS installer + portable .exe
npm run package:dir    # Unpacked directory (for testing)
```

## Architecture

- **Main process** (`src/main/`): Electron window, IPC handlers, Deepgram WebSocket, OpenAI insights, SQLite storage, backend API client
- **Preload** (`src/preload/`): Context bridge exposing safe IPC API to renderer
- **Renderer** (`src/renderer/`): React + Tailwind UI with dark terminal aesthetic matching macOS

### Audio Capture

- **Microphone**: Web Audio API (`getUserMedia` → AudioContext @ 16kHz → ScriptProcessorNode → PCM16)
- **System audio**: Electron `desktopCapturer` → same audio processing pipeline (WASAPI loopback on Windows)
- Audio data flows: Renderer → IPC → Main process → Deepgram WebSocket

### Storage

- Settings: `electron-store` (JSON file in `%APPDATA%`)
- Meetings: SQLite via `better-sqlite3` (file in `%APPDATA%`)
- Device ID: UUID file in `%APPDATA%/.miniti/`

## Tech Stack

- Electron 33
- React 19
- TypeScript 5
- Tailwind CSS 3
- Zustand (state management)
- electron-vite (build tooling)
- better-sqlite3 (meeting persistence)
- ws (Deepgram WebSocket)
- electron-store (settings)
