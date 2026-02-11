# miniti

multi-dimensional meetings

a high-performance macOS + iOS meeting transcription app with real-time speech-to-text and AI-powered insights, built for sales

## Quick Start

### 1. Install

1. Unzip `Miniti.zip`
2. Drag `Miniti.app` to your **Applications** folder
3. The app is **not notarized yet**, so macOS will block it on first launch:
   - **Right-click** (or Control-click) the app → click **Open**
   - A warning appears — click **Open** again to confirm
   - If that doesn't work: open the app normally, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**

After the first open, the app launches normally from then on.

### 2. Permissions

Miniti will ask for two permissions the first time you record. Here's what to expect:

| Permission | When it appears | What to do |
|---|---|---|
| **Microphone** | First time you start recording with mic enabled | Click **Allow** in the system dialog |
| **System Audio Recording** | First time you start recording with system audio enabled | Click **Allow** — this appears under **Privacy & Security → System Audio Recording** (not Screen Recording) |

Both can be managed later in **System Settings → Privacy & Security**.

> **Note**: Miniti only captures audio. It does **not** record your screen, despite macOS grouping audio permissions near screen recording settings.

### 3. Choose your mode

On first launch, pick a mode. You can switch anytime in Settings (`⌘,`).

| Mode | What it means |
|---|---|
| **Early Adopter** (managed) | No API keys needed — 500 free minutes/month of transcription + AI insights |
| **Bring Your Own Keys** (BYOK) | Use your own Deepgram + OpenAI API keys for unlimited usage |

### 4. Record

1. Toggle mic and/or system audio on the home screen
2. Select your transcription model (Nova-2 or Nova-3)
3. Click the start button or press `⌘⇧R`
4. Watch the live transcript — your mic shows as **"You"** (green), remote audio shows as **"Speaker 1"** (blue)
5. Click stop or press `⌘⇧R` when done

## Requirements

### macOS
- **macOS 14.2** (Sonoma) or later
- Apple Silicon or Intel Mac

### iOS
- **iOS 17.0** or later
- iPhone or iPad

## Two Modes

### Early Adopter (Managed)
- **No API keys needed** — just open and go
- 500 free minutes per month of transcription + AI insights
- Usage tracked per device; resets monthly

### Bring Your Own Keys (BYOK)
- Use your own API keys for unlimited usage
- Requires:
  - Deepgram API key ([get one here](https://console.deepgram.com/signup))
  - OpenAI API key ([get one here](https://platform.openai.com/api-keys))
- Enter keys on the home screen or in Settings → API Keys

## macOS Features

### native macOS AI meeting assistant

- mic + system audio recording
- live transcription with deepgram
- live speaker identification
- live AI-generated summaries and action items
- live MEDDPICC analysis
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything

### Core Transcription
- **Real-time Transcription**: Live speech-to-text using Deepgram Nova-2/Nova-3 with ~200ms latency
- **System Audio Capture**: Record audio from video calls (Zoom, Meet, Teams, etc.)
- **Microphone Capture**: Record your own voice
- **Source-based Speaker Separation**: Mic audio is labeled "You", system audio is labeled "Speaker 1/2/..." — no more confusion about who said what
- **Multi-speaker Diarization**: Remote speakers on system audio are still individually identified
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

## Keyboard Shortcuts

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

**You:**
I think we should prioritize the auth flow...

**Speaker 1:**
Agreed, let's scope that out this week...
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

## iOS Features

### mobile AI meeting assistant

- mic recording with background support
- live transcription with deepgram
- live AI-generated summaries and action items
- live MEDDPICC analysis
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

### Recording
- **Microphone Capture**: Record your voice on iPhone or iPad
- **Background Recording**: Keeps recording when you switch apps or lock your phone
- **Live Activity**: Dynamic Island shows recording dot and elapsed timer; Lock Screen shows recording status, meeting title, and live transcript line
- **Live Transcript**: Same real-time transcription as macOS, powered by Deepgram

### AI Insights
- **Live Insights**: Summaries, action items, topics, and discussion flow — same engine as macOS
- **MEDDPICC Mode**: Full sales qualification analysis on mobile
- **Configurable AI Model**: GPT-5 Mini or GPT-5 Nano

### Meeting History
- **Browse Past Meetings**: Searchable list with swipe-to-delete
- **Meeting Detail**: Drill into transcript, insights, and notes for any meeting
- **Persisted with SwiftData**: Shared data model with macOS

### Notes
- **Live Notes**: Take notes during meetings
- **Copy to Clipboard**: Export transcript, insights, or full meeting as markdown

---

## Changelog

### 2026-02-10 - v1.4.0 (current)
- iOS app (MinitiMobile): mic-only recording, live transcription, AI insights, meeting history
- Live Activity with Dynamic Island and Lock Screen: recording status, elapsed timer, live transcript line
- Background recording support on iOS
- Date-based recording timer (fixes background timer drift on iOS)
- Responsive MEDDPICC grid (1 column on iPhone, 2 on iPad/Mac)
- Shared codebase: models, services, and views between macOS and iOS targets

### 2026-02-07 - v1.3.0
- Centralized color palette (ColorPalette.swift) with Theme aliases
- Fix transcript save bug: resumed sessions ("cont") now correctly persist all segments, not just those from the first recording
- Fix sidebar focus rings: buttons use .focusable(false) since all navigation is keyboard-shortcut-driven

### 2026-02-06 - v1.2.0
- Implement onboarding flow and app mode selection (Early Adopter / BYOK)
- Refactor audio capture: Core Audio Process Tap replaces ScreenCaptureKit, adaptive dual AGC, source dominance tracking, mic/system speaker separation
- Revise README for clarity and detail
- Rename app display name to lowercase "miniti"
- Add DMG build script and distribution workflow docs

### 2026-02-05 - v1.1.0
- README: add download section, restructure with user content at top / dev at bottom
- Code signing identity for macOS distribution
- Add empty Secrets.swift for Xcode Cloud builds
- Enhance audio recording and monitoring (home screen pre-flight waveforms)
- Add info popovers for API keys in settings

### 2026-02-05 - v1.0.0
- Initial commit: core app with SwiftUI + SwiftData, Deepgram streaming transcription, OpenAI insights, meeting persistence
- Add API key inputs to home screen
- Restore Secrets.swift fallback for default API keys
- API status pills on home screen (click-to-edit)
- Fix padding syntax error
- Make notes section compact (~3 lines default, resizable)
- Add macOS app icon (all sizes/scales)

---

# Development

## Building from Source

1. Clone the repo
   ```bash
   git clone https://github.com/12ian34/miniti.git
   cd miniti
   ```

2. (Optional) Add default API keys for development:
   ```bash
   cp Miniti/Secrets.example.swift Miniti/Secrets.swift
   # Edit Secrets.swift with your keys
   ```

3. Open in Xcode and run
   ```bash
   open Miniti.xcodeproj
   # Select your Development Team in Signing & Capabilities
   # Build and run (Cmd+R)
   ```

API keys can also be entered on the home screen at runtime.

## Architecture

```
Miniti/                          # macOS target
├── MinitiApp.swift              # App entry + MenuBarExtra
├── Views/
│   ├── MainWindow.swift         # Primary window with sidebar & history
│   ├── MeetingView.swift        # Active meeting UI (transcript + notes + insights)
│   ├── TranscriptView.swift     # Live transcript with speaker colors (shared)
│   ├── InsightsView.swift       # AI insights panel (shared)
│   ├── HistoryView.swift        # Past meetings detail view
│   ├── SettingsView.swift       # Mode toggle, API keys (BYOK), audio, preferences
│   ├── OnboardingView.swift     # First-launch mode selection (shared)
│   ├── UsageBanner.swift        # Usage display for managed mode (shared)
│   └── LimitReachedView.swift   # Hard block at 500 min (shared)
├── Services/
│   ├── AudioCaptureService.swift      # Mic (AVAudioEngine) + system audio (Core Audio Process Tap)
│   ├── DeepgramService.swift          # WebSocket streaming to Deepgram (shared)
│   ├── InsightsService.swift          # OpenAI integration (shared)
│   ├── MinitiAPIService.swift         # Backend communication (shared)
│   ├── DeviceIdentifier.swift         # Keychain-based device UUID (shared)
│   └── KeyboardShortcutsService.swift # Global keyboard shortcuts
└── Models/
    ├── Meeting.swift            # SwiftData models (shared)
    ├── AppState.swift           # Observable app state (shared)
    └── ColorPalette.swift       # Centralized color system (shared)

MinitiMobile/                    # iOS target
├── MinitiApp_iOS.swift          # iOS app entry point
├── AudioCaptureService_iOS.swift # Mic-only audio capture
├── Views/
│   ├── MainTabView.swift        # Tab navigation (Record / History / Settings)
│   ├── MeetingView_iOS.swift    # Mobile recording UI
│   ├── SettingsView_iOS.swift   # iOS settings
│   └── HistoryView_iOS.swift    # Meeting history browser
└── Info.plist

MinitiLiveActivity/              # Widget extension (embedded in iOS app)
├── MinitiLiveActivityBundle.swift
├── MinitiLiveActivityLiveActivity.swift  # Dynamic Island + Lock Screen UI
└── Info.plist

Shared/
└── RecordingActivityAttributes.swift    # ActivityKit attributes (iOS + extension)
```

## Tech Stack

- **UI**: SwiftUI (macOS 14.2+ / iOS 17.0+)
- **Audio Capture**: AVAudioEngine (mic) + Core Audio Process Tap (system audio, macOS only)
- **Speech-to-Text**: Deepgram Nova-2/Nova-3 Streaming API
- **Insights**: OpenAI GPT-5-mini / GPT-5-nano
- **Persistence**: SwiftData
- **Menu Bar**: MenuBarExtra (macOS)
- **Live Activity**: ActivityKit + WidgetKit (iOS)

## License

MIT License
