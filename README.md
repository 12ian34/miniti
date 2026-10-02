# miniti

**Most meeting tools stop at notes. miniti coaches you to speak with clarity and confidence, and you own your transcripts and insights forever.**

miniti is a native meeting assistant for macOS and iOS. It records your meetings without joining as a bot, transcribes them live with speaker identification, writes the summary and action items as the meeting happens, and coaches how you speak. Everything you record stays on your device.

[![Download for Mac](https://img.shields.io/badge/macOS-download%20DMG-3FB950?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/12ian34/miniti/releases/latest)
[![Download on the App Store](https://img.shields.io/badge/iPhone%20%26%20iPad-App%20Store-0A84FF?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/app/id6759067308)
[![Linux](https://img.shields.io/badge/Linux-miniti--linux-FCA311?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/12ian34/miniti-linux)

Website: [miniti.app](https://miniti.app) · Docs: [miniti.app/docs](https://miniti.app/docs) · Changelog: [miniti.app/changelog](https://miniti.app/changelog)

<p align="center">
  <img src="https://miniti.app/images/screens/mac-02-recording.webp" alt="miniti recording a meeting on macOS: live transcript with named speakers on the left, summary and action items on the right" width="900">
</p>

## What it does

- **Records without a bot.** On the Mac it captures your microphone and the system audio of Zoom, Meet, Teams or any call on separate channels, so nobody sees a "miniti has joined" notice. On iPhone and iPad it records the room.
- **Transcribes live, with names.** Deepgram Nova-3 transcription in 11 languages with speaker separation on both channels, including several people sharing one microphone. miniti works out real names from the conversation and your calendar, so "Speaker 2" becomes "Sam". Optional on-device speaker separation runs NVIDIA's Nemotron model on Apple silicon and never sends the speaker decisions anywhere.
- **Writes the summary as you go.** Summary, discussion flow, action items, key decisions and topics update during the meeting, then a final pass runs when you stop. Questions mode suggests incisive things to ask next.
- **Coaches how you speak.** Filler words, talk ratio, pace, longest monologue, questions asked and clarity, per meeting and as trends over time, with grounded examples from your own transcripts.
- **Specialist views when you want them.** Sales analysis with the eight MEDDPICC fields, live templates such as BANT, SPIN, an interview scorecard or a 1:1 (or your own), and a Playbook that answers from your own docs with citations.
- **Knows your calendar.** Google Calendar shows what's next, starts the right meeting at the right time, keeps the event's title and attendees, and hands off cleanly between back-to-back calls. Zoom, Teams, Meet and Slack calls are detected on the Mac so miniti can offer to take notes when a call starts and ask when it ends.
- **Sends things where you work.** Attio and Twenty CRM, webhooks, markdown export to a folder, and a Granola import for your old notes.
- **Keeps your data yours.** Transcripts, notes and insights are saved on your device. Audio goes to Deepgram for the words, text goes to OpenAI for the insights, and nothing else leaves the device. Bring your own API keys and miniti's servers are never in the path at all.

<p align="center">
  <img src="https://miniti.app/images/screens/mac-06-coaching.webp" alt="Coaching view: focus for the next meeting, strengths, and trends across recent meetings" width="900">
</p>

<p align="center">
  <img src="https://miniti.app/images/screens/iphone-02-recording-transcript.webp" alt="iPhone: live transcript" width="220">
  <img src="https://miniti.app/images/screens/iphone-03-recording-insights.webp" alt="iPhone: live insights" width="220">
  <img src="https://miniti.app/images/screens/iphone-07-coaching.webp" alt="iPhone: coaching" width="220">
  <img src="https://miniti.app/images/screens/iphone-09-history.webp" alt="iPhone: meeting history" width="220">
</p>

More screenshots at [miniti.app/screens](https://miniti.app/screens).

## Pricing

| | Minutes | Price |
|---|---|---|
| Free | 500 per month | free |
| Pro | 5,000 per month | $5 per month, covers every device on your account |
| Bring your own keys | unlimited | free, you pay Deepgram and OpenAI directly |

Accounts are an anonymous recovery key. No email, no password, up to five devices.

## Platforms

- **macOS 14.2 or later**, Intel or Apple silicon. Mic plus system audio, a red REC timer in the menu bar, a floating recording surface, keyboard shortcuts, CRM export, markdown auto-export, Sparkle updates.
- **iOS and iPadOS 17 or later.** Background recording, Dynamic Island and Lock Screen Live Activity, adaptive iPad sidebar.
- **Linux** lives in its own repo, [miniti-linux](https://github.com/12ian34/miniti-linux) (Tauri and Rust), and shares the same backend and features.

## Building from source

You need Xcode 26 on macOS 15 or later.

```sh
git clone https://github.com/12ian34/miniti.git
cd miniti
open Miniti.xcodeproj
```

Pick the `Miniti` scheme for the Mac app or `MinitiMobile` for iPhone and iPad, then build and run. The first build fetches the 190 MB Nemotron speaker model from Hugging Face into `Miniti/Resources/NemotronDiarizer/` (pinned and checksummed by `scripts/fetch-nemotron-model.sh`); it needs the network once.

A local build runs in bring-your-own-keys mode: open Settings and enter your [Deepgram](https://deepgram.com) and [OpenAI](https://platform.openai.com) API keys. Managed mode talks to miniti's hosted backend and needs a device enrolment that only shipped builds can complete.

Tests (the same sources run against both apps):

```sh
fastlane mac test
fastlane ios test
```

Signing, notarization and the release process need the project's certificates and are documented in `RELEASE.md` and `fastlane/RUNBOOK.md` for maintainers.

## How it is built

SwiftUI and SwiftData, Swift 6 concurrency. Deepgram Nova-3 over a WebSocket for transcription, OpenAI for insights, NVIDIA Nemotron-3-Diarization through the [FluidAudio](https://github.com/FluidInference/FluidAudio) Core ML port for on-device speaker separation, TypeSafe Jev for sub-second speaker matching, Sparkle for Mac updates, StoreKit and Polar for payments. Every colour routes through `ColorPalette`, every piece of state through `AppState`, and the audio pipeline has a watchdog for each way a Mac can stop sending audio. The licences of the open-source components and models that ship inside the app are listed under Settings → About → Acknowledgements and in `Miniti/Resources/Acknowledgements/`.

## Contributing

Issues and pull requests are welcome. For anything beyond a small fix, open an issue first so we can agree on the approach. Please keep changelog wording in `CHANGELOG.md` plain and user-facing, and add a test next to the code you touch.

## Licence

miniti is a paid product with its source published for transparency and contributions. The code is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may read, build, modify and share it for any noncommercial purpose, and you may not use it for a commercial purpose, which includes selling it, offering it as a service, or shipping it in a competing product. Contact [ian@miniti.app](mailto:ian@miniti.app) for a commercial licence. Use the apps themselves on the terms at [miniti.app/terms](https://miniti.app/terms).

The miniti name and logo are not covered by the licence.
