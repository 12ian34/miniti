# Marketing screenshots

Regenerates every marketing screenshot for the iOS/iPadOS and macOS apps from the
**real app**, with no hand-built mockups and no manual navigation. Each run produces:

- raw captures of every screen, per device, under `out/<device>/<NN>-<scene>.png`
- App Store artwork (headline + capture in a device frame) written straight into
  `fastlane/screenshots/en-US/`, ready for `fastlane ios screenshots`
- macOS hero cards under `out/framed/` for the website, social posts, and bulletins

```sh
scripts/screenshots/build.sh              # one Debug build per platform
scripts/screenshots/capture-ios.sh iphone # every iOS scene on the iPhone simulator
scripts/screenshots/capture-ios.sh ipad   # same scenes on the 13" iPad simulator
scripts/screenshots/capture-mac.sh        # every macOS scene
scripts/screenshots/render_frames.py --ios-out fastlane/screenshots/en-US --mac-out scripts/screenshots/out/framed
```

or all of it in one go with `scripts/screenshots/all.sh`. Afterwards, look at every PNG
before shipping it: a green run proves the app rendered a scene, not that the scene is
the one you want on the store.

## Smoke gate

`scripts/screenshots/smoke.sh [ios|mac|all]` is the launch-and-render check from roadmap
P0.6. It builds both Debug apps and runs every scene into `out-smoke/` (never the marketing
`out/`). A run passes only if each macOS scene opens its window, renders, writes its PNG,
and exits 0, and each iOS scene reaches first layout: the app writes
`<container>/tmp/miniti-screenshot-ready-<scene>` after the settle delay, and
`capture-ios.sh` fails the scene when that marker is missing, which is the only way to tell
a crash from a blank capture because `simctl launch` returns as soon as the process starts.
Two scenes exist only for this gate: `store-recovery` (the P0.2 screen, rendered from a
synthetic corruption failure with the seeded store as the read-only export source) and
`persistence-issue` (Home with the P0.3 "didn't save" banner). Quit the installed Miniti
first on macOS; the capture build refuses to run beside it.

## How it works

The app has a **screenshot mode**, switched on by the `-MinitiScreenshotScene <scene>`
launch argument (Debug builds only, `Miniti/ScreenshotMode.swift`). In that mode the app:

- uses an in-memory SwiftData store seeded with a fixed set of realistic meetings, so
  History, Coaching, and saved-meeting detail have content and never touch real data;
- skips the terms, onboarding, and force-update gates, and stubs the network: usage
  shows as a managed Pro account, calendar shows seeded upcoming events, and no
  Deepgram, OpenAI, or backend call is made;
- for the `recording-*` scenes, puts `AppState` into a live-recording state with a
  canned transcript, speaker names, insights, questions, coaching metrics, and MEDDPICC,
  plus a frozen elapsed timer and a static waveform;
- selects the tab, sidebar destination, and insights sub-tab the scene names.

On iOS the shell script then takes the PNG with `simctl io screenshot` under a 9:41
status-bar override. On macOS the app writes its own window image into its sandbox
container (`~/Library/Containers/com.miniti.app/Data/tmp/`), because a terminal without
Screen Recording permission cannot capture another app's window; the script moves it
into `out/mac/`. The window is sized to 1440×900 points, so the PNG is 2880×1800 on a
Retina display. The Debug build shares its container with the installed app, so quit
Miniti before capturing; the app snapshots and restores your defaults around each run
and never opens the real meeting store.

`render_frames.py` then reads `frames/store-frames.html`, finds every fixed-size
element with a `data-screen-label`, drops the captures into its `<img>` slots, and
screenshots each card at its declared size with headless Google Chrome (or Playwright
when installed). A card whose capture is missing fails the run and writes nothing.

## Scenes

| iOS / iPadOS | macOS |
|---|---|
| `01-home` — upcoming calendar meetings | `01-home` |
| `02-recording-transcript` | `02-recording` — transcript + notes + insights |
| `03-recording-insights` — summary tab | `03-recording-sales` — MEDDPICC |
| `04-recording-sales` — MEDDPICC | `04-recording-questions` |
| `05-recording-questions` | `05-meeting` — saved meeting detail |
| `06-recording-coaching` | `06-coaching` — Coaching focus |
| `07-coaching` — Coaching focus | `07-coaching-stats` |
| `08-coaching-stats` | `08-settings` |
| `09-history` | |
| `10-meeting` — saved meeting detail | |
| `11-settings` | `09-recording-template` — Templates view (BANT) |
| `12-recording-template` — Templates view (BANT) | `10-meeting-coaching` — saved meeting, coaching tab |
| `13-meeting-coaching` — saved meeting, coaching tab | `11-settings-account` — Settings, Account & Plan |
| `14-store-recovery` — smoke gate only: P0.2 recovery screen | `12-store-recovery` — smoke gate only |
| `15-persistence-issue` — smoke gate only: P0.3 banner on Home | `13-persistence-issue` — smoke gate only |
| `16-settings-templates` — Settings, Templates with one custom template | `14-settings-templates` |

Scene lists live in `env.sh`; the app-side switch is `ScreenshotScene` in
`Miniti/ScreenshotMode.swift`. Adding a scene means: add a case there, add it to the
list in `env.sh`, and (if it should ship) reference it from a card in
`frames/store-frames.html`.

## Editing the store artwork

The copy is plain text in `frames/store-frames.html`; a wording change is an edit there
and a re-render, no capture or build needed. Card sizes are the App Store's:
1320×2868 (iPhone 6.9"), 2064×2752 (iPad 13"), and 2880×1800 for the Mac hero. Open the
file in a browser next to a populated `out/` directory to preview all cards at once.

`render_frames.py --list` prints every card and where it lands;
`--only "iPhone 1,iPad 2"` re-renders a subset.

## Uploading

`fastlane ios screenshots` uploads `fastlane/screenshots/en-US` to App Store Connect and
replaces the existing set for each device class. Run it after eyeballing the PNGs.

## Seed data

The seeded meetings, transcript, insights, and calendar events are in
`Miniti/ScreenshotMode.swift`. They are deliberately plausible B2B content with no real
names of customers. Change them there when the product story changes.

## Locales

App Store Connect has en-US and en-GB listings. `all.sh` mirrors the rendered en-US frames into `fastlane/screenshots/en-GB` because deliver only replaces the locales it finds files for; a missing locale keeps its old screenshots. `fastlane ios screenshot_sets` lists what is on App Store Connect for the editable version, and `prune:true` deletes sets for display types the repo no longer ships (for example the old 6.5-inch iPhone set).
