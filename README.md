# Miniti

A high-performance macOS meeting transcription app with real-time speech-to-text and AI-powered insights. Built with a terminal-aesthetic UI for developers and sales professionals.

## Features

### Core Transcription
- **Real-time Transcription**: Live speech-to-text using Deepgram Nova-2/Nova-3 with ~200ms latency
- **System Audio Capture**: Record audio from video calls (Zoom, Meet, Teams, etc.)
- **Microphone Capture**: Record your own voice
- **Speaker Diarization**: Automatically identifies and color-codes different speakers
- **Live Transcript View**: See transcription appear in real-time with smooth auto-scrolling

### AI Insights
- **Live Insights**: Summaries, action items, topics, and discussion flow update during recording
- **Auto-updating Titles**: Meeting names update based on conversation content
- **Configurable AI Model**: Choose between GPT-5 Mini (higher quality) or GPT-5 Nano (faster)
- **Multiple Insight Modes**:
  - **Standard**: General meeting insights (summary, actions, topics, discussion flow)
  - **MEDDPICC**: Sales qualification framework for discovery calls

### Notes
- **Live Notes**: Take notes during meetings in a resizable panel below transcript
- **Persisted**: Notes are saved with each meeting
- **Editable**: Edit notes for historical meetings too
- **Copy to Markdown**: Export notes with one click

### Export
- **Copy to Markdown**: One-click copy for transcript, notes, and insights
- **Formatted Output**: Clean markdown with speaker labels, action item checkboxes, and structured sections

### Menu Bar
- **Always Accessible**: Hexagon icon in menu bar with quick access to controls
- **Live Recording Indicator**: Animated pulsing dot when recording
- **Quick Actions**: Start/stop recording, generate insights, open main window
- **Status Display**: Current meeting info, segment count, recording duration

### UI/UX
- **Terminal-style Design**: Dark, monospace aesthetic for developers
- **Linear-style Shortcuts**: Keyboard shortcuts displayed directly on buttons
- **Side-by-side View**: Transcript and insights displayed together
- **Resizable Panels**: VSplitView for transcript/notes, HSplitView for content/insights
- **Session Management**: Meetings move to history immediately after stopping

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧R` | Start/Stop Recording |
| `⌘N` | New Session |
| `⌘H` | Go Home |
| `⌘1` | Standard Mode |
| `⌘2` | MEDDPICC Mode |
| `⌘⇧I` | Generate Insights |
| `⌘,` | Settings |
| `⌘/` | Show All Shortcuts |
| `↑` / `K` | Navigate History Up |
| `↓` / `J` | Navigate History Down |
| `Esc` | Close Overlay / Go Home |

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac
- Deepgram API key (for transcription)
- OpenAI API key (for insights)

## Setup

1. Open `Miniti.xcodeproj` in Xcode
2. Select your Development Team in the project settings
3. Build and run (Cmd+R)
4. Enter your API keys on the home screen:
   - **Deepgram API Key**: Get one at [console.deepgram.com](https://console.deepgram.com/signup)
   - **OpenAI API Key**: Get one at [platform.openai.com](https://platform.openai.com/api-keys)

Keys are stored locally and persist across app restarts.

**For developers**: Copy `Miniti/Secrets.example.swift` to `Miniti/Secrets.swift` and add your keys there - they'll be picked up as defaults.

## Permissions

The app requires:

- **Microphone**: To capture your voice during meetings
- **Screen Recording**: To capture system audio from other applications

Grant these permissions when prompted, or enable them in System Settings > Privacy & Security.

## Usage

1. Select your transcription model (Nova-2 or Nova-3) on the home screen
2. Click "relax and take notes" or press `⌘⇧R` to start recording
3. Speak or play audio from a video call
4. Watch the live transcript and insights update in real-time
5. Take notes in the notes panel below the transcript
6. Switch insight modes with `⌘1` (Standard) or `⌘2` (MEDDPICC)
7. Click "stop" or press `⌘⇧R` when the meeting ends
8. Meeting automatically moves to history - browse with `↑`/`↓` or `J`/`K`
9. Copy transcript, notes, or insights to markdown with the `md` buttons

## Architecture

```
Miniti/
├── MinitiApp.swift              # App entry + MenuBarExtra
├── Views/
│   ├── MainWindow.swift         # Primary window with sidebar & history
│   ├── MeetingView.swift        # Active meeting UI (transcript + notes + insights)
│   ├── TranscriptView.swift     # Live transcript with speaker colors
│   ├── InsightsView.swift       # AI insights panel
│   ├── HistoryView.swift        # Past meetings detail view
│   └── SettingsView.swift       # API keys & preferences
├── Services/
│   ├── AudioCaptureService.swift      # Mic + system audio capture
│   ├── DeepgramService.swift          # WebSocket streaming to Deepgram
│   ├── InsightsService.swift          # OpenAI integration
│   └── KeyboardShortcutsService.swift # Global keyboard shortcuts
└── Models/
    ├── Meeting.swift            # SwiftData models + markdown export
    └── AppState.swift           # Observable app state + markdown export
```

## Tech Stack

- **UI**: SwiftUI (macOS 14+)
- **Audio Capture**: AVAudioEngine (mic) + ScreenCaptureKit (system audio)
- **Speech-to-Text**: Deepgram Nova-2/Nova-3 Streaming API
- **Insights**: OpenAI GPT-5-mini / GPT-5-nano
- **Persistence**: SwiftData
- **Menu Bar**: MenuBarExtra

## Transcription Models

Select your transcription model before recording:

| Model | Pros | Cons |
|-------|------|------|
| **Nova-2** | Lower latency, battle-tested, slightly cheaper | Less accurate diarization |
| **Nova-3** | Better diarization, higher accuracy, handles accents better | Slightly higher latency |

## AI Models

Select your AI model in the insights panel:

| Model | Pros | Cons |
|-------|------|------|
| **GPT-5 Mini** | Higher accuracy, better reasoning, more nuanced | Slower, higher cost |
| **GPT-5 Nano** | 2x faster, lower cost, great for real-time | Less detailed, may miss nuances |

## Insight Modes

### Standard Mode
Best for general meetings. Extracts:
- Summary of discussion
- Discussion flow (chronological topics)
- Action items
- Key topics/themes

### MEDDPICC Mode
Best for sales discovery calls. Extracts qualification criteria:

| Letter | Meaning | What it captures |
|--------|---------|------------------|
| M | Metrics | Quantifiable success measures mentioned |
| E | Economic Buyer | Who controls budget/final decision |
| D | Decision Criteria | Factors influencing their decision |
| D | Decision Process | Their buying/evaluation process |
| P | Paper Process | Legal, procurement, security review steps |
| I | Identify Pain | Problems they're trying to solve |
| C | Champion | Internal advocate for your solution |
| C | Competition | Other solutions they're considering |

## Markdown Export

Click the `md` button on any section header to copy formatted markdown:

**Transcript** exports with speaker labels:
```markdown
## Transcript

**Speaker 1:**
Hello everyone, let's get started...

**Speaker 2:**
Thanks for joining...
```

**Insights** exports with structure:
```markdown
## Insights

### Summary
Brief overview of the meeting...

### Discussion Flow
1. Opening introductions
2. Product demo walkthrough
3. Q&A session

### Action Items
- [ ] Send follow-up email
- [ ] Schedule next meeting

### Topics
- Product roadmap
- Pricing discussion
```

## License

MIT License
