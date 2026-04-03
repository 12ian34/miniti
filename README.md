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
| **Early Adopter** (managed) | No API keys needed — 500 free minutes/month (upgrade to Pro for 5,000) |
| **Bring Your Own Keys** (BYOK) | Use your own Deepgram + OpenAI API keys for unlimited usage |

### 4. Record

1. Toggle mic and/or system audio on the home screen
2. (Optional) Click **test audio** to verify your mic and system audio are working
3. (Optional) Pick a language from the dropdown (defaults to English)
4. Click the start button or press `⌘⇧R`
5. Watch the live transcript — your mic shows as **"You"** (green), remote audio shows as **"Speaker 1"** (blue)
6. Click stop or press `⌘⇧R` when done

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

## Tiers

| | Free | Pro | BYOK |
|---|---|---|---|
| **Price** | $0 | $5/month | $0 (forever) |
| **Minutes** | 500/month | 5,000/month | Unlimited |
| **API keys needed** | No | No | Yes (your own) |

### Free (Managed)
- **No API keys needed** — just open and go
- 500 free minutes per month of transcription + AI insights
- Usage tracked per device; resets monthly

### Pro (Managed)
- Everything in Free, with 5,000 minutes per month
- Upgrade from Settings or when the free limit is reached
- macOS: one-click checkout via web; iOS: in-app subscription ($4.99/month)

### Bring Your Own Keys (BYOK)
- Use your own API keys for unlimited usage
- Requires:
  - Deepgram API key ([get one here](https://console.deepgram.com/signup))
  - OpenAI API key ([get one here](https://platform.openai.com/api-keys))
- Enter keys on the home screen or in Settings → API Keys

## Which Tier Should I Choose?

Choose **Free** if:

- You want the fastest setup (no API keys)
- You are evaluating the app
- 500 minutes/month is enough for your usage

Choose **Pro** if:

- You need more than 500 minutes/month but want zero setup
- You prefer a managed service without handling API keys

Choose **BYOK** if:

- You want full control of your API usage and costs
- You already have Deepgram + OpenAI accounts

Your BYOK keys stay saved when switching modes — you can switch back later.

## macOS Features

### native macOS AI meeting assistant

- mic + system audio recording
- live transcription in 11 languages with deepgram nova-3
- live speaker identification
- live AI-generated summaries and action items
- live MEDDPICC analysis
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- google calendar integration — upcoming meetings, auto-start/stop, attendee context, auto Attio sync
- meeting history browser
- native menu bar controls
- keyboard shortcuts for everything

### Core Transcription
- **Real-time Transcription**: Live speech-to-text using Deepgram Nova-3 with ~200ms latency
- **11 Languages**: English, Spanish, French, German, Portuguese, Italian, Dutch, Swedish, Greek, Polish, Russian — pick per meeting or set a default
- **System Audio Capture**: Record audio from video calls (Zoom, Meet, Teams, etc.)
- **Microphone Capture**: Record your own voice
- **Source-based Speaker Separation**: Mic audio is labeled "You", system audio is labeled "Speaker 1/2/..." — no more confusion about who said what
- **Multi-speaker Diarization**: Remote speakers on system audio are still individually identified
- **Live Transcript View**: See transcription appear in real-time with smooth auto-scrolling

### AI Insights
- **Live Insights**: Summaries, action items, topics, and discussion flow update during recording
- **Auto-updating Titles**: Meeting names update based on conversation content
- **Multiple Insight Modes**:
  - **Standard**: General meeting insights (summary, actions, topics, discussion flow)
  - **MEDDPICC**: Sales qualification framework for discovery calls

### Notes
- **Live Notes**: Take notes during meetings in a resizable panel below transcript
- **Persisted**: Notes are saved with each meeting
- **Editable**: Edit notes for historical meetings too
- **Copy to Markdown**: Export notes with one click

### Export & Integrations
- **Copy to Markdown**: One-click copy for transcript, notes, and insights
- **Formatted Output**: Clean markdown with speaker labels, action item checkboxes, and structured sections
- **Auto-export to Local Folder (macOS)**: Automatically save meetings as markdown files to a local folder (default `~/Documents/miniti/`). Works with Obsidian, Claude Code, and other tools. Optional `CLAUDE.md` index file for AI agent discovery. Enable in Settings → Integrations.
- **Attio CRM Send (Saved Meetings)**: Send a saved meeting summary to Attio (people or companies) with optional task creation from action items
- **Google Calendar (macOS)**: See upcoming meetings, auto-start/stop recording, pass attendee context to AI, auto-sync to Attio
- **Outbound Webhooks**: POST meeting data as JSON to any URL when a meeting is saved or insights are updated — works with Zapier, Make, n8n, and custom endpoints. Configure in Settings.

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
- **Full-text Search**: Search across meeting titles, transcripts, notes, insights, topics, action items, MEDDPICC, and discussion flow. Press `/` to focus the search field.
- **Session Management**: Stop a recording to review, then resume, save, or discard
- **Auto-stop Recording**: Automatically stops recording when no speech is detected for a configurable duration (off, 3, 5, 10, or 15 minutes)
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
| `/` | Search Meetings |
| `↑` / `K` | Navigate History Up |
| `↓` / `J` | Navigate History Down |
| `Esc` | Close Overlay / Go Home |

## Supported Languages

Record and transcribe in 11 languages. Set a default in Settings or pick per meeting before recording. Transcription, AI insights, and filler word detection all adapt to the selected language.

| Language | Code |
|----------|------|
| 🇬🇧 English | en |
| 🇪🇸 Español | es |
| 🇫🇷 Français | fr |
| 🇩🇪 Deutsch | de |
| 🇵🇹 Português | pt |
| 🇮🇹 Italiano | it |
| 🇳🇱 Nederlands | nl |
| 🇸🇪 Svenska | sv |
| 🇬🇷 Ελληνικά | el |
| 🇵🇱 Polski | pl |
| 🇷🇺 Русский | ru |

All transcription uses Deepgram Nova-3. All insights use GPT-5 Mini.

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
| Filler words | Counts of "um", "uh", "like", "basically", etc. — per type, per speaker, per minute. Language-specific defaults with custom overrides. |
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

Click the `copy` button on any section header to copy formatted markdown:

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

## Google Calendar Integration (macOS)

Connect your Google Calendar to see upcoming meetings and streamline recording.

### What it does

- **Upcoming meetings**: Shows your next 5 calendar events on the home screen
- **Auto-start**: Counts down and starts recording when a meeting begins (configurable)
- **Auto-stop**: Shortens the silence timeout after a calendar event ends, so recording stops sooner when the meeting is over
- **Attendee context**: Passes meeting attendees to AI insights for better speaker attribution and analysis
- **Auto Attio sync**: Automatically sends meeting summaries to Attio after saving, if attendees match an Attio record

### Setup

1. Open **Settings** (`⌘,`) → **Integrations** → **Google Calendar**
2. Toggle on **Enable Google Calendar**
3. Click **Connect** and sign in with your Google account
4. Configure auto-start, auto-stop, and auto Attio sync toggles as needed

### Notes

- Google Calendar integration is macOS-only
- Only reads your calendar events (read-only access) — miniti never creates or modifies events
- Calendar events refresh every 5 minutes
- Auto-start shows a countdown banner with "start now" and "dismiss" options
- Dismissed events are tracked so they don't prompt again

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

- The app now tries to auto-recover after route/profile changes (for example AirPods switching call modes)
- Allow up to ~20 seconds for automatic system-audio recovery after a device switch
- If audio still looks stuck after that window, stop/resume the session or start a fresh session (`⌘N`)
- For deeper diagnosis, open the [debug log](#debug-log) (5 taps on version in Settings)

### Managed mode says limit reached / recording is blocked

- Free tier has a 500 minute monthly cap; Pro has 5,000 minutes
- Upgrade to Pro, switch to **BYOK** for unlimited usage, or wait for the monthly reset

### Attio issues

- **"Send to Attio" is missing**: Enable it in **Settings → General → Integrations**
- **Can't search**: Connect your Attio account first, then enter at least 2 characters
- **Attio backend endpoints are not deployed yet**: Your backend deployment does not include Attio routes yet
- **0 tasks created**: The meeting may not contain usable action items, or Attio may accept the note but not create tasks from the parsed items

## iOS Features

### mobile AI meeting assistant

- mic recording with background support
- live transcription in 11 languages with deepgram nova-3
- live AI-generated summaries and action items
- live MEDDPICC analysis
- training mode — filler words, talk ratio, pace, monologue detection, questions, clarity
- meeting history browser
- Live Activity on Dynamic Island and Lock Screen (timer + live transcript)
- dark mode terminal-style UI

### Recording
- **Microphone Capture**: Record your voice on iPhone or iPad
- **11 Languages**: Same multilingual support as macOS — pick per meeting or set a default
- **Background Recording**: Keeps recording when you switch apps or lock your phone
- **Live Activity**: Dynamic Island shows recording dot and elapsed timer; Lock Screen shows recording status, meeting title, and live transcript line
- **Live Transcript**: Same real-time transcription as macOS, powered by Deepgram Nova-3
- **Auto-stop Recording**: Automatically stops recording when no speech is detected for a configurable duration

### AI Insights
- **Live Insights**: Summaries, action items, topics, and discussion flow — same engine as macOS
- **MEDDPICC Mode**: Full sales qualification analysis on mobile

### Integrations
- **Outbound Webhooks**: POST meeting data as JSON to Zapier, Make, n8n, or any endpoint when a meeting is saved or insights update

### Meeting History
- **Browse Past Meetings**: Full-text searchable list with swipe-to-delete
- **Meeting Detail**: Drill into transcript, insights (including MEDDPICC), training stats, and notes for any meeting
- **Editable Titles**: Rename saved meetings from the history detail view
- **Generate/Update Insights**: Generate or refresh saved-meeting insights, including MEDDPICC
- **Editable Notes**: Add or edit notes on saved meetings
- **Persisted with SwiftData**: Shared data model with macOS

### Notes
- **Live Notes**: Take notes during meetings
- **Copy to Clipboard**: Export transcript, insights, or full meeting as markdown

## Debug Log

A built-in debug log viewer helps diagnose audio, transcription, and connection issues.

### How to open it

1. Open **Settings** (`⌘,` on macOS, gear icon on iOS)
2. Scroll to the **About** section
3. Tap the **version number** 5 times quickly

The debug log opens as a terminal-style viewer with:
- Category filters (audio, deepgram, app)
- Pretty and raw view modes (raw mode supports text selection for partial copy)
- Copy and clear buttons

The debug log contains structured diagnostic data only — never transcript content or audio.

## Links

These links are also available in the app under **Settings → About**.

- [Website](https://miniti.app)
- [Roadmap](https://miniti.app/roadmap)
- [Changelog](https://miniti.app/changelog)
- [Privacy Policy](https://miniti.app/privacy)
- [Terms of Service](https://miniti.app/terms)

## Contact

For support, questions, or feedback: **miniti@ianahuja.com**

---

## License

Copyright (c) 2026 moonquake tech. All rights reserved.

This software is proprietary and confidential. No part of this software may be reproduced, distributed, modified, reverse engineered, decompiled, or used to create derivative works without the prior written permission of the copyright holder.

Unauthorized copying, distribution, or use of this software, in whole or in part, is strictly prohibited.
