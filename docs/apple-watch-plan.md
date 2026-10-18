# Apple Watch meeting recording

Planned 2026-10-18. Research and repository inspection only; no watch target or implementation exists yet. The user selected **record on the watch, generate the transcript and notes afterwards**. Delivery priority and release version are not assigned. The [roadmap](roadmap.md#p36-apple-watch-recording) owns sequencing and completion tracking.

## Product decision

Build a small native watchOS companion to the iPhone app. The watch records its own microphone to local storage, including when the phone is out of range or there is no internet. After the recording ends, transfer it to the paired iPhone, transcribe the saved audio, and generate the usual summary and action items. The iPhone microphone is not involved.

The iPhone is required for setup and subsequent processing in v1, but need not be present during recording. Cellular service on the watch is not required for this architecture. A Mac alone is not the companion: Watch Connectivity connects a watchOS app to its paired iPhone app. Finished meetings can reach the Mac through existing cloud sync, which remains optional, Pro-only, managed-only, and default off. Watch-to-phone transfer must work without subscribing to cloud sync.

The capture use case is conversations within microphone range, such as walking 1:1s and in-person meetings. Do not promise capture of remote participants heard only through another device's headphones, or reuse the Mac's system-audio claims. Room coverage, wind, clothing noise, battery life, and useful meeting length need real-device measurement.

## Verified feasibility and Granola comparison

- Apple documents foreground-initiated audio recording that continues in the background on watchOS. Use the supported audio background mode and microphone permission. Screen dimming and returning to the watch face must be tested. Calls, Siri, resource pressure, and battery loss still require interruption handling. Do not use a workout or mindfulness session to keep a meeting recorder alive. [Apple background modes](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html), [Apple watchOS app lifecycle session](https://developer.apple.com/videos/play/wwdc2017/216/).
- Watch Connectivity transfers files and state to the paired iPhone. Background delivery is opportunistic, so nearby devices do not imply an immediate transfer or an always-running phone process. [Apple Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity), [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession).
- Granola's own help page explicitly describes watch microphone capture, offline recording, transfer to iPhone, and subsequent processing. It documents continued recording with a lowered wrist or another app in front, transfer/processing states, retry controls, and syncing partial audio after interruptions. This is directly comparable to the selected miniti experience. Its current minimum is watchOS 11; that is Granola's choice, not a platform requirement miniti inherits. [Granola watch guide](https://docs.granola.ai/help-center/ios/apple-watch).
- Deepgram has a prerecorded REST API with speaker diarization and an asynchronous callback option. This is the appropriate starting point for finished watch recordings; do not replay a meeting through the live socket at real-time speed. [Deepgram prerecorded API](https://developers.deepgram.com/reference/speech-to-text/listen-pre-recorded).

These sources were checked on 2026-10-18. Background behavior and provider contracts must be rechecked during implementation.

## Repository fit and gaps

| Area | Current repository | Required work |
|---|---|---|
| Targets | `Miniti`, `MinitiMobile`, Live Activity extension, two test bundles | Add a native SwiftUI watchOS app embedded with `MinitiMobile`, its scheme, signing, assets, permissions, and tests. Choose the minimum watchOS version after the hardware spike. |
| Capture | `MinitiMobile/AudioCaptureService_iOS.swift` converts microphone buffers to 16 kHz mono PCM16 and passes them to live transcription | Separate lightweight watch recorder that writes durable audio files. Prototype `AVAudioRecorder` with speech-quality mono AAC. Do not compile the full iOS audio service into watchOS. |
| Connectivity | No `WCSession` / Watch Connectivity integration found | Watch and iPhone connectivity services, durable transfer inbox/outbox, versioned metadata, deduplication, receipt acknowledgements, retries, and status reconciliation. |
| Transcription | `Miniti/Services/DeepgramService.swift` handles live sockets or the optional local engine | New saved-audio transcription path and result mapping. Preserve word timing, language, diarization, dictionary settings, and existing speaker identity conventions. |
| Meeting storage | `Meeting` has transcript relationships, import provenance, and no saved-audio field | Keep transfer/processing jobs separate from live meeting state. Reuse existing provenance fields if suitable; test any schema additions against existing stores. |
| Insights | `AppState.generateInsightsForMeeting(_:)` already generates insights for a saved transcript | Reuse the services and persistence rules with an immutable job configuration. The existing UI-mode-dependent function needs adaptation before a background job can safely call it. |
| Startup / persistence | `MinitiMobile/MinitiApp_iOS.swift` creates `AppState`; `modelContext` is wired by the first root view | Register Watch Connectivity early and persist received files even if onboarding, store recovery, or background launch prevents a view appearing. Import only after the persistent store is available. |
| Managed backend | `/api/session` grants live Deepgram access; `/api/session/end` caps minutes by server wall-clock elapsed time | Define saved-audio admission, duration accounting, job identity, completion, and retries. A 60-minute recording processed in a few minutes cannot use live-session elapsed time as its usage cap. |
| Cloud | Finished `Meeting` documents already sync, with privacy and entitlement gates | Sync only a complete imported transcript, then its later insights update. Keep raw audio and processing placeholders outside the existing meeting sync document. |

Keep the watch target independent of the large `AppState`, FluidAudio models, Sparkle, StoreKit purchase UI, and desktop/mobile feature views. Share small `Sendable` transfer types and compatible design tokens. The iPhone remains the authority for account, API keys, settings, entitlements, and meeting history; the watch owns local recording state. Avoid spreading a third platform through existing `#if os(iOS) ... #else` branches.

## First-version experience

1. Open miniti on the watch and tap Record. Start locally after permission and storage checks, without waiting for phone reachability or a provider request. Confirm actual capture with a haptic and visible recording state.
2. Show elapsed time, a restrained microphone indicator, and a large Stop action. A watch-face complication can open this screen. Start capture from the foreground after user action.
3. Lower the wrist or return to the watch face while recording continues. On interruption, preserve the captured portion and clearly show that recording stopped. Resuming the same recording is outside the initial scope.
4. Stop saves the recording and places it in a persistent queue. Show `saved on watch`, `waiting for phone`, or `sending to phone` as appropriate, with retry and delete controls for saved items.
5. The iPhone durably accepts the recording, then shows `waiting to process`, `transcribing`, `generating notes`, `ready`, or an actionable retry state. Do not promise immediate processing when iOS has suspended or force-quit the app; opening the phone app must resume pending work.
6. The finished transcript and notes appear in normal iPhone History with watch provenance. Mac availability follows existing cloud settings. No live transcript, coaching, questions, or insights on the watch in v1.

Start with ad-hoc meetings. Calendar selection/reminders, broader watch history, pause/resume, App Intents/Action Button, live transcription, direct cellular uploads, and independent watch accounts are later decisions. A phone remote-control mode would be a separate feature with a clearly identified microphone and its own iOS background-start feasibility test.

## Durable recording and transfer contract

Use a recording UUID created on the watch as the stable identity through transfer, processing, usage, and meeting import. Metadata should include protocol version, capture start/end, actual captured duration, language, file format, size/checksum, and any later calendar context. Capture duration and transcript offsets must reflect the actual audio, including any gaps, rather than transfer time.

- Write audio and a manifest incrementally to Application Support, exclude temporary audio from backups, and do not buffer a whole meeting in RAM. Choose a container/checkpoint strategy that preserves valid partial audio after termination; an unfinalized AAC container is a spike risk, not an assumed guarantee. Measure roughly 22 MB/hour at 48 kbps mono AAC, excluding overhead; choose the final format from quality, battery, recovery, and transfer results.
- Use `WCSession.transferFile(_:metadata:)` for finalized audio and durable queued messages/context for receipts and status. Do not use `sendMessage` as a continuous audio transport or as the only record of a receipt.
- The phone moves/copies the incoming temporary file into its own durable inbox inside the receive callback, verifies it, and records the receipt before acknowledging it. Transport completion alone does not prove that meeting processing succeeded.
- Retries and duplicate deliveries must find the same local job and eventual meeting, never create a second meeting or bill a second time. Reject conflicting metadata for the same identity. Recover the ledger and pending transfers after relaunch.
- Preserve a recoverable audio copy until transcript persistence succeeds. After a durable phone receipt the watch copy may be cleaned up under a documented policy; the phone must retain its copy through transcription failure. Delete remaining temporary audio after the successful transcript commit. A failed summary can retry from the transcript without audio.
- Interrupted recordings remain visible as partial recordings. Low storage must produce a clear stop/error with recoverable audio. Do not silently discard queued meetings or rely on a termination callback to save them.
- Account switches while recordings are pending require an explicit ownership decision before upload. Bind jobs to an opaque account/configuration context, prevent silent submission under a different account or API-key configuration, and never send recovery keys, provider keys, bearer tokens, or installation private keys to the watch.
- Import jobs must not overwrite or end an active phone recording, change the selected insight mode, resurrect a deleted meeting, or trigger duplicate webhook/CRM sends. Deletion/cancellation must invalidate later results and perform temporary-file cleanup. Cloud pulls must retain their existing no-outbound-side-effects rule.

## Processing, quotas, and privacy

First prove transcription and transcript-to-meeting mapping in a foreground BYOK spike. Then select the production upload design from measured evidence:

- **Direct phone-to-Deepgram upload:** less new infrastructure, using the phone's BYOK key or a managed short-lived authorization. Validate prerecorded authorization, background file uploads/result delivery, credential expiry, provider completion verification, and crash recovery. New managed admission/accounting is still required.
- **Managed asynchronous job:** the phone obtains a bounded upload destination, uploads outside the ordinary Vercel JSON route, and the backend submits an asynchronous Deepgram request. Persist job/result state, verify callbacks, enforce temporary-audio expiry/deletion, and allow the phone to retrieve results on its next launch. This adds temporary storage and job infrastructure, but can decouple provider processing from phone execution time. It is not implemented by the current cloud-sync storage contract.

Do not proxy an entire hour-long file through an ordinary serverless request or assume that background task time permits a long synchronous transcription. Select one managed architecture after the spike; document exact endpoints and retention in `../miniti-api/docs/agents/` before implementing them. BYOK credentials stay on the phone, and any BYOK processing that cannot complete in the background waits for foreground execution with an honest status.

Proposed quota policy: local capture may complete offline, but managed processing checks current account entitlement and quota before incurring provider cost. If quota is insufficient, retain the recording and offer retry after reset or an account/mode change; never discard it. Reserve capacity atomically and settle once from validated audio/provider duration using the recording/job ID. Specify reservation expiry, partial failures, retry ambiguity, account-wide concurrency, and month-boundary behavior. A stale watch quota snapshot is informational only. No watch subscription or extra managed device slot is needed when all backend calls originate from the enrolled phone.

Cloud transcription sends audio to Deepgram and notes generation sends transcript content to OpenAI. This remains separate from optional cloud history sync. Offline capture does not make subsequent processing on-device or eligible for private-mode claims. Respect existing privacy gates and per-meeting cloud exclusions. Never silently upload a private recording; unsupported private/local processing must remain blocked and explained. Update privacy/support copy to describe temporary watch/phone audio and any new server retention before release.

## Delivery gates

### 1. Real-watch capture spike

Create the smallest recorder and transfer experiment on physical hardware before building feature UI. Test a representative older supported watch and a current model where available. Run 5-, 30-, and 60-minute sessions; measure audio intelligibility, timestamps, file size, transfer time, battery use, memory, and heat. Test phone absent, internet absent, wrist down, watch face, another app, phone locked, Siri/call interruptions, low power, and low storage. Recover partial files after an app kill or restart. Set the minimum OS and any duration limit from results.

**Exit:** a documented 60-minute recording remains continuous through ordinary background use, transfers intact after reconnecting, and interruption/termination tests either recover valid audio or clearly identify the bounded loss. Do not claim zero loss on power failure without evidence.

### 2. Durable iPhone import and saved-audio transcription

Implement the versioned transfer protocol, persistent queue, durable receipts, duplicate protection, and saved-audio parser. Import the transcript through the existing persistence coordinator with stable meeting/segment identities, then generate saved-meeting insights without depending on live UI state. Test a pending import while the phone records another meeting, store startup failure, app relaunch, deletion, and changed account/settings. Select the managed processing architecture and quota policy.

**Exit:** one recording yields one correct saved meeting, failures can retry, and audio is retained until a durable transcript exists.

### 3. Managed path and watch product UI

Implement the selected authenticated processing/accounting contract and BYOK path, then the compact watch UI, queue/status screens, and complication. Reuse phone setup and subscription management. Validate language/dictionary propagation, diarization, summary/title/action items, optional cloud sync, account changes, quota exhaustion, and temporary-audio cleanup. Add a same-day `miniti-linux` tracking issue before implementing any shared backend or sync contract changes, as required by `AGENTS.md`; no Linux watch app is implied.

**Exit:** offline capture through ready notes works in both managed and BYOK modes, with durable retry and accurate usage, without changing phone/Mac recording behavior.

### 4. Release verification

Add meaningful protocol/import/accounting tests and watch-specific tests; run both existing macOS and iOS suites. Repeat the physical-watch matrix and paired iPhone background/force-quit/reboot tests. Archive the iOS app with its embedded watch app and verify installation/signing via TestFlight. Update architecture/audio/testing/distribution docs, privacy and support documentation, watch screenshots and App Store metadata, then release notes. Ship only after the capture and recovery gates pass.

No implementation or release estimate is committed by this planning pass. The next concrete work item is the real-watch recording and transfer spike.
