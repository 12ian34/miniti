# miniti

multi-dimensional meetings

a high-performance macOS + iOS meeting transcription app with real-time speech-to-text and AI-powered insights, built for sales

## Quick Start

### 1. Install

1. Download the DMG from the link provided
2. Open the DMG and drag `miniti.app` to your **Applications** folder
3. Launch from Applications — the app is signed and notarized

### 2. Permissions

miniti will ask for two permissions the first time you record. Here's what to expect:

| Permission | When it appears | What to do |
|---|---|---|
| **Microphone** | First time you start recording with mic enabled | Click **Allow** in the system dialog |
| **System Audio Recording** | First time you start recording with system audio enabled | Click **Allow** — this appears under **Privacy & Security → System Audio Recording** (not Screen Recording) |

Both can be managed later in **System Settings → Privacy & Security**.

> **Note**: miniti only captures audio. It does **not** record your screen, despite macOS grouping audio permissions near screen recording settings.

### 3. Choose your mode

On first launch, pick a mode. You can switch anytime in Settings (`⌘,`).

| Mode | What it means |
|---|---|
| **Early Adopter** (managed) | No API keys needed — 500 free minutes/month of transcription + AI insights |
| **Bring Your Own Keys** (BYOK) | Use your own Deepgram + OpenAI API keys for unlimited usage |

### 4. Record

1. Toggle mic and/or system audio on the home screen
2. (Optional) Choose transcription + AI models in Settings (`⌘,` on macOS)
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
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
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
- **Resizable Panels**: Drag handle for transcript/notes split, HSplitView for content/insights
- **Session Management**: Stop a recording to review, then resume, save, or discard
- **Historical Insights Tabs**: Saved meetings on macOS include standard / MEDDPICC / training views with `⌘1` / `⌘2` / `⌘3`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧R` | Start/Stop Recording |
| `⌘N` | New Session |
| `⌘H` | Go Home |
| `⌘1` | Standard Mode |
| `⌘2` | MEDDPICC Mode |
| `⌘3` | Training Mode |
| `⌘⇧I` | Generate Insights |
| `⌘,` | Settings |
| `⌘/` | Show All Shortcuts |
| `↑` / `K` | Navigate History Up |
| `↓` / `J` | Navigate History Down |
| `Esc` | Close Overlay / Go Home |

## Transcription Models

Select your transcription model in Settings (macOS: `⌘,` → Models):

| Model | Pros | Cons |
|-------|------|------|
| **Nova-2** | Lower latency, battle-tested, slightly cheaper | Less accurate diarization |
| **Nova-3** | Better diarization, higher accuracy, handles accents better | Slightly higher latency |

## AI Models

Select your AI model in Settings (macOS: `⌘,` → Models):

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

### Training Mode
Analyzes your speech patterns in real-time to help you become a better communicator. All metrics are computed locally from the transcript — no LLM calls, no API keys needed.

| Metric | What it measures |
|--------|------------------|
| Filler words | Counts of "um", "uh", "like", "basically", etc. — per type, per speaker, per minute |
| Talk ratio | How much of the conversation each speaker occupies |
| Speaking pace | Words per minute for each speaker |
| Longest monologue | Longest uninterrupted speaking stretch |
| Questions asked | Number of questions per speaker |
| Clarity | Average words per turn — shorter turns tend to be clearer |

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
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
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
- **Meeting Detail**: Drill into transcript, insights (including MEDDPICC), training stats, and notes for any meeting
- **Editable Titles**: Rename saved meetings from the history detail view
- **Generate/Update Insights**: Generate or refresh saved-meeting insights, including MEDDPICC
- **Editable Notes**: Add or edit notes on saved meetings
- **Persisted with SwiftData**: Shared data model with macOS

### Notes
- **Live Notes**: Take notes during meetings
- **Copy to Clipboard**: Export transcript, insights, or full meeting as markdown

---

## License

Copyright (c) 2026 miniti. All rights reserved.

This software is proprietary and confidential. No part of this software may be reproduced, distributed, modified, reverse engineered, decompiled, or used to create derivative works without the prior written permission of the copyright holder.

Unauthorized copying, distribution, or use of this software, in whole or in part, is strictly prohibited.
