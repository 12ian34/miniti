# Automatic in-room and hybrid meeting diarization

## Status and decision

This is the implementation plan for distinguishing several people speaking into the Mac's physical microphone while preserving the existing mic-versus-system separation used for online calls. The plan's code-level claims were verified against the codebase and Deepgram streaming documentation on 2026-08-23; sections below name the verified contact points and known regression traps.

**Implementation status (shipped in v2.5.0 on 2026-08-23):** Phases 1–3 and the user-facing Phase 4 presentation are implemented. `TranscriptSource` and `SpeakerIdentityState` (generation-aware collision-free allocation, mic `1000 + n`, single-mic reconnect continuity, relaunch seeding) live in `DeepgramService`; the channel-0 flattening and the dead `sourceLookup` energy path are removed; source flows through `SpeakerSegment` → `LiveSegment.source` → save snapshots → the additive optional `TranscriptSegment.sourceRaw`. The implicit "You" applies only to dual-source (mic+system) sessions and legacy meetings, and is withdrawn once a second mic speaker is confirmed; mic-only recordings keep neutral labels unless explicitly marked. **Amendment (v2.7.0, in progress):** when environment inference is `remoteLikely`, keep "You" on the primary mic speaker even if additional mic IDs appear (headset clones). The "no assumption that the first mic speaker is the user" rule stays in force for `unknown`, `inRoomLikely`, and `hybridLikely`. Cumulative-final dedup is source-aware; reconnects preserve names/marks; mic-range labels render as "Speaker N (mic)". The environment inference engine (`MeetingEnvironmentInferenceEngine` in `CallLifecyclePolicy.swift`) is internal/diagnostic-only, fed lazily from call-lifecycle, calendar conference URLs (`selectedCalendarEvent.joinURL` / meet/conference fields), confirmed mic-speaker counts, and per-source meaningful finals, persisted as optional `Meeting.inferredEnvironmentRaw`, logged plus counted via privacy-safe diagnostic events. The managed backend and BYOK speaker-naming prompts understand the mic ID range without assigning any ID to the device owner absent transcript evidence. Synthetic dual-channel fixtures and both platform test bundles cover the deterministic contract; the real-room audio matrix remains an operational field-validation watchlist.

The product decision is:

> Miniti infers the meeting environment automatically. The user does not choose an online, in-person, or hybrid meeting type, and there is no new meeting-type setting or preflight question.

This plan continues to use Deepgram cloud transcription and diarization. It is not an on-device diarization project. The existing managed and BYOK routing, minute limits, privacy disclosures, and Deepgram credential flow remain unchanged.

Deepgram documents speaker diarization for live streaming and supports combining it with multichannel transcription when a channel itself contains several speakers:

- [Deepgram speaker diarization](https://developers.deepgram.com/docs/diarization/)
- [Deepgram multichannel and diarization guidance](https://developers.deepgram.com/docs/multichannel-vs-diarization)

Verified 2026-08-23: `diarize_model=latest` is valid on streaming and resolves to the **v1** streaming diarizer — the improved v2 diarizer is batch-only. Phase 0 must therefore set quality expectations from real streaming behaviour, not batch demos or the v2 changelog. Diarization with multichannel is per-channel, and speaker numbering restarts at 0 on each channel, so provider IDs overlap across channels and across reconnects.

The internal inference must never be required for transcript correctness. Miniti should preserve Deepgram's per-speaker labels on the microphone channel in every capture topology, then use call-app, calendar, transcript-source, and speaker evidence to describe the environment internally. The user experience remains simply `Start meeting`; distinct speakers appear when Deepgram finds them. A late or wrong classification may affect diagnostic state, but must not drop audio, merge speakers, reconnect the socket, expose a correction workflow, or change a meeting boundary by itself.

## User problem

The normal macOS recording path sends microphone and system audio as two Deepgram channels. This correctly separates the local microphone from remote/system speakers, but Miniti currently replaces every microphone-channel speaker with the reserved speaker ID `1000` and labels all of it `You`.

That is correct for a typical one-person-at-a-Mac call, but wrong for:

- an in-person meeting with several people around one Mac;
- a hybrid meeting with several people in the room and additional remote attendees;
- a conference-room microphone shared by several local participants;
- a remote call where someone beside the user speaks into the same microphone.

Mic-only recording already retains Deepgram's native speaker labels because the mono path does not apply the macOS microphone override (verified: `sourceLookup` is assigned `nil` on every connect path, so the legacy energy rewrite is dead code and mono words pass through untouched). Note the flip side of that: in a mic-only recording today, no segment ever carries ID `1000`, `isLocalMic` is false for everything, and nobody is presented as `You` unless manually marked. The missing capability is therefore not a new transcription provider or local model. It is a source-aware speaker identity model that also preserves those labels in the normal dual-channel path.

## Non-negotiable product contract

- No online/in-person/hybrid selector.
- No first-run question, recording-start prompt, or persistent setting for meeting type.
- No meeting-type badge or classification-correction workflow in the first release.
- No automatic socket topology switch based only on silence or missing system transcript.
- No fully local or bundled diarization model in this programme.
- No raw audio retention after the existing capture pipeline has finished with a buffer.
- No assumption that the first, nearest, or loudest microphone speaker is the user.
- No loss of current remote-speaker diarization, echo reconciliation, chronological ordering, speaker naming, Coaching, insights, save/recovery, export, webhook, CRM, managed-usage, or BYOK behaviour.
- Manual rename and `mark as you` remain correction tools for speaker identity, not a meeting-type workflow.

## Why absence of system transcript is supporting evidence only

No system-channel transcript is consistent with an in-person meeting, but it is not proof. The same observation occurs when:

- a remote participant has not spoken yet;
- the user joins early, muted, or listen-only;
- a supported call application has not acquired the microphone;
- a call uses an unsupported application or unusual browser process;
- transcription is delayed or recovering;
- the meeting is a solo note or dictation rather than a meeting.

Conversely, system speech does not always prove an online meeting: a person may play a video, podcast, or voice message during an in-person meeting.

The inference must combine independent signals, retain an `unknown` state when evidence is weak, and allow stronger later evidence to supersede earlier evidence. It must not perform an irreversible action.

## Proposed internal model

Keep capture topology, speaker source, and inferred environment separate.

### Capture topology

This remains a mechanical description of what is being sent to Deepgram:

- `microphoneOnly`
- `systemOnly`
- `microphoneAndSystem`

For the default macOS dual-source case, continue sending interleaved stereo PCM with microphone on channel 0 and system audio on channel 1. Continue requesting both `multichannel=true` and `diarize_model=latest`.

### Speaker source

Add an explicit source to live and persisted transcript segments:

- `microphone`
- `system`
- `unknown` for legacy or malformed responses

Do not continue inferring source from `speaker == 1000`. `LiveSegment.isLocalMic`, Coaching presentation, colors, echo reconciliation, exports, and diagnostics must read the explicit source.

Deepgram speaker numbers are channel-local and may overlap. Allocate collision-free app speaker IDs while retaining the provider ID and source long enough to test and debug attribution. A compatible first mapping is:

- system speaker `n` -> existing low app ID range;
- microphone speaker `n` -> app ID `1000 + n`, preserving `1000` for the first microphone speaker and legacy meetings.

A bare `1000 + n` formula is **not** collision-free across reconnects: Deepgram numbering restarts at 0 on every new WebSocket, so the same formula reassigns the same app IDs to potentially different people. The allocator must be connection-generation-aware from day one — the durable design treats `(source, providerSpeakerID, connectionGeneration)` as the provider identity and the app speaker ID as its presentation/persistence key. Do not scatter arithmetic assumptions through views.

This also changes a documented invariant. `docs/patterns.md` states that `micSpeakerID` survives reconnect precisely because it is a synthetic app ID and *not* a Deepgram diarization ID; `resetSpeakerIdentityForDeepgramReconnect` (`AppState.swift`) keeps only the key `"1000"` in live names/overrides/self IDs, and `testResetSpeakerIdentityForDeepgramReconnectKeepsOnlyMicIdentity` pins that behaviour. Making mic app IDs provider-derived means that function, its test, and the patterns.md contract must be revised together, deliberately. (System-channel provider IDs already collide across reconnects today with only cosmetic mitigation — the mic side must not inherit that bug.)

### Inferred environment

Maintain an internal, evidence-backed state:

- `unknown`
- `remoteLikely`
- `inRoomLikely`
- `hybridLikely`

This state is internal and is not shown as a choice or status badge. It may be persisted as optional metadata for recovery, diagnostics, and future product behaviour, but old meetings must decode as `unknown` without migration failure.

The state is monotonic only with respect to evidence strength, not enum order. For example, `inRoomLikely` must become `hybridLikely` when a system-channel participant later speaks.

## Evidence and inference policy

Implement the policy as a small deterministic value-type state machine, separate from `AppState`, with table-driven tests.

### Strong remote evidence

- The recording starts associated with a recognized call application from the call-lifecycle monitor.
- A finalized, meaningful system-channel transcript arrives while an associated call app is active or a linked calendar event has a conference URL.

### Supporting remote evidence

- The linked calendar event has a conference URL.
- Exactly one recognized call application is active at recording start but association is temporarily incomplete.
- A finalized, meaningful system-channel transcript arrives without independent call or calendar evidence.
- Sustained system speech-like audio accompanies microphone speech.

### Strong in-room evidence

There is no single immediate strong signal. `inRoomLikely` requires a bounded observation window and a combination such as:

- meaningful finalized microphone transcript exists;
- Deepgram has confirmed at least two microphone-channel speakers;
- no finalized system-channel transcript has arrived during the observation window;
- no recognized call application is associated or active;
- the calendar event has no conference URL, when calendar context exists.

The initial observation window should be a policy constant selected from fixtures and field measurement rather than guessed in UI code. Start evaluation around 30 seconds of meaningful speech, not merely 30 seconds of wall time.

### Hybrid evidence

- At least two confirmed microphone-channel speakers plus a finalized meaningful system-channel transcript and associated call-app or conference-calendar evidence; or
- at least two confirmed microphone-channel speakers plus an associated call application and sustained system speech evidence over the observation window.

### Unknown and conflicting evidence

Remain `unknown` when the evidence is sparse or conflicting. A single microphone speaker with no system transcript is not enough to distinguish an in-person conversation, solo note, quiet remote call, or unsupported call app.

Played media can produce a system transcript during an in-room meeting. Until there is associated call-app or calendar evidence, treat that as a weak remote signal and keep the environment unknown rather than changing meeting-boundary policy.

## Transcript and speaker behaviour

### Dual-source parsing

Remove the unconditional microphone-channel rewrite in `DeepgramService.processTranscriptJSON`. Preserve Deepgram's diarized `word.speaker` for channel 0 and map it to a microphone app speaker ID. Preserve the existing system speaker mapping for channel 1.

Speaker-change stabilization must run independently per channel. A speaker confirmed on the system channel must not make the same numeric provider ID look confirmed on the microphone channel. Pending evidence and confirmed speaker sets therefore need a source/channel-aware key (today `SegmentationState` keys both by bare `Int`).

Three additional verified mechanics in the current code must be handled explicitly, or they regress:

- `AppState.mergeFinalSegment` deduplicates cumulative Deepgram finals only when `existing.speaker == newSegment.speaker`. Today every mic final carries `1000`, so cumulative mic finals always find their predecessor; once real mic diarization is preserved, a cumulative final whose diarized speaker flips between passes is appended as duplicate text instead of merged. The same speaker-equality guard sits under `mergeStoppedInterimTranscript`, which commits the last interim at stop using the interim's dominant speaker. Dedup must become content/source-aware, with a fixture test for a cumulative mic final that changes speaker ID.
- `segmentBySpeaker` currently exempts `micSpeakerID` from both the switch-confidence check and the new-speaker promotion gate (`DeepgramService.swift`). Once mic words carry real diarized IDs, mic speech loses that exemption and short mic turns must earn promotion (6 words / 1.5 s / 0.65 confidence) like system speakers — a behaviour change on the primary user's own speech. Decide per-source thresholds deliberately; a naive port swallows short mic utterances and regresses the single-user remote call the acceptance bars protect.
- The interim speaker gate in `handleTranscriptUpdate` only trusts speakers already present in `detectedSpeakers`, which is populated from finals. A newly appearing second mic speaker's first interim therefore renders under the stale current speaker until their first final lands. Acceptable if understood, but it belongs in the fixture matrix.

### Echo reconciliation

Keep the current text/time/source-energy reconciliation. A likely playback duplicate on the microphone channel is still suppressed even though it now carries a diarized microphone speaker ID. Genuine simultaneous local speech remains eligible for release with its original speaker identity.

Tests must cover an echo assigned to a different microphone speaker ID than the surrounding local speech. Suppression is based on overlapping content and source evidence, not speaker-number equality.

### Identifying the user

Do not automatically mark the first microphone speaker as `You` once multiple microphone speakers are present. That is an attractive but unreliable shortcut.

- For a remote-likely meeting with exactly one confirmed microphone speaker, retain the current effective `You` presentation.
- If a second microphone speaker is confirmed, preserve distinct neutral labels unless automatic speaker naming confidently resolves identities.
- If speaker-name inference identifies the connected user's own name with adequate evidence, it may propose or apply the existing self mapping under a separately tested confidence contract.
- Otherwise, the existing rename and `mark as you` controls provide an optional correction path. The meeting continues normally without requiring correction.

No insight request should wait for the user's identity to be resolved. Coaching must clearly distinguish per-speaker metrics from user-specific metrics and avoid silently attributing the whole room to the user.

The implicit default self set `[micSpeakerID]` is replicated independently in at least seven places (`AppState.effectiveLiveSelfSpeakerIDs`, `Meeting.effectiveSelfSpeakerIDs`, `TrainingMetrics.compute`, `CoachingExampleExtractor.resolvedSelfIDs`, `SelectableTextView.turnDisplayKey`, and the `TranscriptView` legend and color helpers). With several microphone speakers, any mic ID missing from the self set silently counts as a *remote* speaker in talk ratio, turn grouping, and the Coaching self bucket — and real-time nudges stop firing on macOS because `realtimeNudgeTargetSpeakerIDs` has no single-speaker fallback there. Phase 2 must route these through one shared self-set/source resolution rather than editing each site's arithmetic.

### Speaker naming and reconnects

Automatic speaker naming should receive source-aware, collision-free speaker IDs and continue using calendar attendees as hints. IDs resolving to the same real name may use the existing display merge behaviour.

Two verified traps here. First, the naming prompt currently hard-codes `1000` as "the device's microphone (the user)" — in the BYOK client prompt (`InsightsService.swift`) *and* in the managed backend's `speaker_names` prompt in `miniti-api`; preserving several mic speakers makes that sentence wrong, and the managed fix is a backend deploy, not an app change. Second, `speakerNameHasTranscriptEvidence` requires the self-identifying segment to carry the exact speaker ID being named; splitting one person's speech across mic IDs splits the evidence and can reject a name that passes today.

Deepgram speaker IDs reset on a new WebSocket. The first implementation may preserve the current reconnect reset contract, but it must allocate new app identities without colliding with earlier speakers. Re-inferred identical names can merge presentation later. Stable voice matching across reconnects is a separate enhancement and must not block this programme.

## Capture routing and cost

The first release must keep the current socket topology for the selected audio sources. In particular, default dual-source recording stays dual-source even after Miniti infers that a meeting is probably in-room.

This deliberately pays the existing two-channel Deepgram cost for correctness and reversibility. Automatically reconnecting from stereo to mono after a quiet system-channel window would:

- risk missing the first remote speech after the switch;
- reset Deepgram timestamps and speaker identities;
- complicate echo reconciliation and durable ordering;
- turn a probabilistic environment label into a destructive capture decision.

After production evidence demonstrates classifier precision, a separate cost-optimization plan may evaluate automatic mono downshift with buffered handoff. It is not part of this implementation and must have an explicit transcript-loss acceptance bar.

If the user has already disabled system capture, the existing mono microphone path continues naturally and receives the same source-aware speaker handling. This is an audio-source preference, not a meeting-type selection.

## Interaction with Smart meetings and call lifecycle

The call-lifecycle monitor is a high-value input, not a dependency for correct diarization.

- An associated active call app supports `remoteLikely`.
- Several microphone speakers do not weaken an observed call-app end signal; hybrid rooms still have calls.
- `inRoomLikely` with no associated call app continues to use the existing conservative quiet/calendar fallback.
- Environment inference must never start, stop, split, or transition a meeting directly.
- Call-lifecycle reliability failures are `no information`, not in-room evidence.

This preserves the boundaries and consent contract in [call-lifecycle-and-recording-presence-plan.md](call-lifecycle-and-recording-presence-plan.md).

## Persistence and compatibility

Prefer additive optional fields so existing SwiftData stores remain lightweight-migratable:

- optional source on `TranscriptSegment`;
- optional inferred-environment value on `Meeting`, if persistence proves useful;
- no rewrite of historical speaker IDs.

Legacy segments without a source continue to use the current speaker-ID fallback for display. New code must not require source metadata to load, trim, export, search, or regenerate insights for an old meeting.

The save payload, interrupted-meeting recovery, transcript snapshots, webhook payload, CRM export, Markdown export, Granola import, and transcript trimming paths must either carry source explicitly or document why they safely collapse it. External payload schemas should not change without backend compatibility tests.

Verified status of those paths today: all Markdown/clipboard exports and the webhook transcript serialize resolved *labels*, not raw IDs, so they collapse safely; the CRM payloads (Attio/Twenty) carry no speaker data at all; Granola import already flattens all self turns to `1000`. Two webhook fields do move and need a documented decision rather than incidental change: `speaker_count` is a raw distinct-ID count that inflates under per-speaker mic IDs, and `speaker_names` keys leak raw app IDs to external consumers.

## Implementation phases

### Phase 0 — validate the provider contract

- Capture a dual-channel fixture containing two microphone speakers and two system speakers.
- Confirm current Deepgram streaming responses retain diarized speaker IDs independently on both channels when `multichannel=true` and `diarize_model=latest` are combined.
- Record callback ordering, provider-ID overlap between channels, interim churn, final stability, and behaviour after reconnect.
- Stop if the production Deepgram contract differs from its documentation; do not design around guessed response semantics.

Deliverable: a small checked-in sanitized/synthetic response fixture and a written result in this plan.

### Phase 1 — source-aware identity foundation

- Add the source type and collision-free mapping in the service/model layer.
- Make segmentation confirmation source-aware.
- Carry source through live segments, pending echo/order buffers, saves, and reloads.
- Replace `speaker == micSpeakerID` source checks with explicit source checks while retaining legacy fallbacks.
- Add lightweight-migration and legacy-meeting tests.

No user-visible behaviour changes in this phase.

### Phase 2 — preserve microphone diarization

- Stop flattening channel 0 to one speaker.
- Retain separate microphone speakers through interim and final rendering.
- Update echo reconciliation, ordering, speaker lists, renaming, automatic naming, Coaching, insights, exports, webhooks, and CRM payloads.
- Update the label/color helpers that assume a single mic ID: `LiveSegment.speakerLabel` and `TranscriptSegment.speakerLabel` hard-code `speaker == 1000 ? "You" : "Speaker \(speaker + 1)"` (a mic speaker `1001` renders as "Speaker 1002"), `investigationMeetingContext` and the insights transcript builder `transcriptText(from:)` re-derive labels the same way instead of using `resolvedSpeakerLabel`, and `speakerColor(for:)` assigns non-self colors modulo seven so mic `1001` collides with system speaker `0`.
- Update real-time nudge targeting and the shared self-set resolution described above.
- Ensure a normal one-user remote call still presents simply as `You` plus remote speakers.

Note that echo reconciliation itself is already mechanically safe: mic/system discrimination in `handleDualSourceFinalSegments` is by `channelIndex`, and `isLikelyEcho` / pending-release are keyed on text, time, energy, and segment UUID — never on speaker number. The echo tests in the test plan guard behaviour, not a rewrite.

### Phase 3 — automatic environment inference

- Plumb the evidence feeds first — two of them do not exist yet as consumable signals. `CalendarEvent.meetLink`/`conferenceUrl` are decoded in `MinitiAPIService.swift` but currently have zero consumers and are not persisted into meeting context, and `CallLifecycleEngine.associatedApp` is `private(set)` on the engine and only logged by `AppState`. Both need explicit accessors (and the conference URL needs to be carried into calendar/meeting context) before the state machine can read them.
- Add the pure inference state machine and evidence snapshot.
- Feed it call-lifecycle, calendar conference URL, confirmed speaker counts, finalized transcript channels, and bounded audio evidence.
- Keep the state internal and diagnostic initially.
- Do not change capture routing or meeting boundaries.

### Phase 4 — product polish and rollout

- Make the resulting multi-speaker transcript understandable without exposing a meeting-type control, badge, or correction workflow.
- Ensure unresolved self identity does not make Coaching misleading.
- Add privacy-safe counters for inferred state, transition reason, time-to-confidence, speaker count, and manual speaker corrections. Never log transcript, attendee names, raw audio, meeting title, browser URL, or unknown bundle IDs.
- Roll out behind a local/remote configuration flag if needed, then remove the flag only after the acceptance matrix passes.

## Test plan

### Deterministic tests

- Dual-channel Deepgram fixtures with overlapping provider speaker IDs.
- Two and three microphone speakers with one or more system speakers.
- Segmentation confirmation and pending evidence isolated per source.
- Mic echo suppressed without merging genuine local speakers.
- Genuine overlapping local/system speech retained and chronologically ordered.
- Interim speaker churn does not pollute the confirmed speaker list.
- A cumulative mic final whose diarized speaker differs from the earlier partial merges instead of duplicating.
- Short mic turns near the promotion thresholds, in single-user and multi-user recordings.
- Reconnect creates collision-free identities and preserves timestamp order.
- Environment-inference table covering call-app, calendar, channel transcript, multiple-mic-speaker, unreliable-monitor, and conflicting-evidence combinations.
- `inRoomLikely -> hybridLikely` when late system speech appears.
- No classification event changes capture topology or invokes start/stop/transition.
- Save/reload, interrupted recovery, transcript trim, speaker rename, `mark as you`, speaker-name inference, Coaching, exports, webhook, and CRM compatibility.
- Legacy meetings without source or environment metadata.

The shared `MinitiTests/*.swift` sources compile in both `MinitiTests` and `MinitiMobileTests`; both bundles must remain green even though the dual-channel runtime is macOS-only.

### Manual matrix

- Two, three, and four people around a MacBook microphone.
- External USB conference microphone.
- Normal Zoom/Meet/Teams call with one local user.
- Hybrid meeting with two local and two remote speakers.
- Browser call with delayed first remote speech.
- Remote listen-only or muted start lasting several minutes.
- In-room meeting that plays a video or voice message.
- Headphones versus speakers, including playback echo.
- Unsupported call application.
- System-audio permission denied or system capture disabled.
- Deepgram reconnect, network loss, microphone route change, Bluetooth handoff, pause/resume, interrupted-meeting recovery, and app relaunch.
- Long meeting with automatic speaker naming, live insights, Coaching, final insights, saved history, export, and CRM sync.

## Acceptance bars

- A microphone shared by multiple people produces stable distinct speakers without requiring a meeting-type choice.
- A standard remote call retains the current simple `You`/remote presentation and does not regress echo suppression.
- A hybrid meeting retains distinct in-room speakers and distinct remote speakers.
- Late system speech can strengthen or revise the inferred environment without reconnecting or losing transcript.
- A false or unresolved environment inference cannot alter audio routing, start/stop behaviour, persistence, usage reporting, or transcript content.
- Existing meetings load without migration errors or changed labels.
- Both XCTest bundles pass, both app targets build, and the manual audio matrix shows no transcript-loss, ordering, reconnect, or recovery regression.

## Explicitly deferred

- Fully on-device diarization, sherpa-onnx, CoreML speaker embeddings, and bundled speaker models.
- Voice enrollment or biometric identification of the user.
- Automatic stereo-to-mono cost optimization.
- Persisting or exporting raw audio.
- A user-facing meeting-type selector or setting.
- Stable voice matching across separate meetings.
