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

## End-to-End Workflow (Recommended)

Use this flow for the smoothest experience on macOS:

1. Start a session (`⌘⇧R`)
2. Talk normally while transcript + insights update live
3. Stop when you want to review (`⌘⇧R`)
4. Review transcript, notes, and insights
5. Resume if needed (same session, no duplicate meeting)
6. Save the session (`⌘S`) when finished
7. Review the saved meeting in History (opens automatically after save on macOS)
8. Export markdown or send to Attio (saved meetings only)

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

## Which Mode Should I Choose?

Choose **Early Adopter (managed)** if:

- You want the fastest setup (no API keys)
- You are evaluating the app
- 500 minutes/month is enough for your usage

Choose **BYOK** if:

- You need more than 500 minutes/month
- You want full control of your API usage/costs
- You already have Deepgram + OpenAI accounts

What changes between modes:

- **Managed**: usage is tracked per device and capped monthly; keys are not required
- **BYOK**: no built-in usage cap, but you must provide your own API keys
- Your BYOK keys stay saved when switching modes (you can switch back later)

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
- **Attio CRM Send (Saved Meetings)**: Send a saved meeting summary to Attio (people or companies) with optional task creation from action items

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
- **Collapsible Panes**: Collapse the sidebar (`⌘[`) or insights pane (`⌘]`) to focus on transcript/notes
- **Session Management**: Stop a recording to review, then resume, save, or discard
- **Stopped Session Shortcuts**: Save (`⌘S`) or discard (`⌘⌫`) directly from the stopped session view
- **Historical Insights Tabs**: Saved meetings on macOS include standard / MEDDPICC / training views with `⌘1` / `⌘2` / `⌘3`

## Keyboard Shortcuts

macOS shortcuts only. Some shortcuts are context-dependent (for example, save/discard require an active session; `⌘1` / `⌘2` / `⌘3` apply in insights views).

| Shortcut | Action |
|----------|--------|
| `⌘⇧R` | Start/Stop Recording |
| `⌘N` | New Session |
| `⌘S` | Save Current Session |
| `⌘⌫` | Discard Current Session |
| `⌘H` | Go Home |
| `⌘[` | Toggle Sidebar |
| `⌘]` | Toggle Insights Pane |
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

### How to Use Training Mode (Practical Guide)

Training mode is best for coaching yourself on delivery, not grading a meeting overall.

Suggested workflow:

1. Switch to **Training** (`⌘3`) during a live session or while reviewing a saved meeting
2. Focus on **one metric at a time** (for example, fillers or talk ratio)
3. Compare similar meeting types (demo vs discovery vs interview), not everything against one target
4. Use the info buttons next to metrics for quick guidance and rough ranges
5. Track trends across sessions instead of overreacting to one meeting

How to interpret the metrics:

- **Fillers**: Lower is usually better; spikes are normal during brainstorming or complex explanations
- **Talk ratio**: Depends on your role (presenter vs interviewer vs coach)
- **Pace**: Fast is not always better; clarity usually drops when pace gets too high
- **Longest monologue**: Useful for spotting when you are not leaving room for questions
- **Questions asked**: Directional signal only; quality matters more than raw count
- **Clarity**: Lower average words/turn often feels easier to follow (`lower = clearer = better`)

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

## Attio Integration (macOS)

Use Attio export to send a saved meeting summary to an Attio person or company record.

### What it sends

- Summary
- Discussion flow
- Action items
- Key decisions
- Topics
- MEDDPICC fields (if available)
- Notes

It does **not** send:

- Full transcript
- Training metrics

### Before you start

1. Open **Settings** (`⌘,`)
2. Go to **General**
3. Turn on **Enable "Send to Attio"** in the **Integrations** section

### How to send a meeting to Attio

1. Open a **saved meeting** in macOS History
2. Click **send to attio**
3. If prompted, click **connect** and complete Attio sign-in in your browser
4. Choose whether to search **people**, **companies**, or **both**
5. Search and select the target Attio record
6. (Optional) Enable **create tasks from action items**
7. Click **send to attio**

### Notes

- Attio export is available for **saved meetings** (history), not active live sessions
- Your Attio selection is remembered per meeting, so you can reopen and resend/update later
- If no action items are detected, task creation is disabled automatically
- If your backend deployment does not include Attio endpoints yet, the app will show a clear error instead of failing silently

## History & Saved Meetings Guide

### macOS

- Use the sidebar to browse saved meetings
- Open a meeting to view:
  - Transcript
  - Insights (Standard / MEDDPICC / Training)
  - Notes
- Use `⌘1`, `⌘2`, `⌘3` to switch insight modes
- Click **update** (or **generate**) to refresh saved-meeting insights
- Edit notes directly in the saved meeting view
- Rename meeting titles in history
- Delete meetings from history (with confirmation)

### iOS

- Open the **History** tab to browse saved meetings
- Tap a meeting to open transcript, insights, training stats, and notes
- Swipe to delete meetings from the list
- Edit title and notes from the meeting detail view
- Generate/update saved-meeting insights (including MEDDPICC)

### Tips

- Training metrics for saved meetings are computed from transcript data (no extra setup)
- If a meeting has no transcript content, training and some insight sections may be empty
- Attio export is available from macOS saved meeting detail only

## Troubleshooting

### I can't start recording / no transcript appears

- Check microphone permission in **System Settings → Privacy & Security → Microphone**
- On macOS, if using system audio, also check **System Audio Recording** permission
- In BYOK mode, confirm your Deepgram and OpenAI keys are set in **Settings → API Keys**
- In managed mode, check for an error message on the home/recording screen (service availability or connection issue)

### macOS system audio is missing

- Make sure **Capture System Audio** is enabled in Settings
- Confirm macOS system audio permission is granted
- Try stopping and starting the session after granting permission

### Bluetooth headphones/audio devices changed and audio looks wrong

- Stop and resume the session after the device switch if needed
- If audio still looks stuck, start a fresh session (`⌘N`)
- Use the debug log (hidden Settings shortcut if you use it internally) only for deeper diagnosis

### Managed mode says limit reached / recording is blocked

- Managed mode has a monthly usage cap (500 minutes)
- Wait for the reset date shown in the app, or switch to **BYOK** for unlimited usage

### Attio issues

- **"Send to Attio" is missing**: Enable it in **Settings → General → Integrations**
- **Can't search**: Connect your Attio account first, then enter at least 2 characters
- **Attio backend endpoints are not deployed yet**: Your backend deployment does not include Attio routes yet
- **0 tasks created**: The meeting may not contain usable action items, or Attio may accept the note but not create tasks from the parsed items

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
