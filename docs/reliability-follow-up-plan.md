# Reliability follow-up: permissions, async state, retries and clear settings

## Status and scope

Planned, approved by Ian on 2026-10-26. The R-series items have no release number; U1 and U2 were assigned to 3.4.0 build 139 the same day (see [account-sending-consent-ux-plan.md](account-sending-consent-ux-plan.md)). The audit examined app `0a0961d` and backend through `3512172`; the enrollment incident notes were then reviewed at app `963b236`. The cross-repository tracker is [roadmap.md](roadmap.md), P0.11. This work is separate from the ownership migrations in [enrollment-identity-plan.md](enrollment-identity-plan.md), Track B. On 2026-10-26 Ian also approved the Sending and consent UX slices U1/U2 below. Optional email-first account protection is specified once in that plan, B6a; it can ship ahead of the ownership migrations.

Ian accepted audit findings 1, 3, 4, 5 and the four other findings. Finding 2, disabling configured webhooks/CRM in private mode, was **rejected**: private mode means keeping meeting data under the person's control. Deliberately configured exports remain permitted. Do not add an export ban, erase outbox items, or change export defaults under this plan. Sending copy must distinguish external AI processing from user-controlled exports and describe the running session accurately.

| Slice | Change | Platform / repository | State |
|---|---|---|---|
| R1 | Private-mode transitions match the running transcription session | macOS, miniti | planned |
| R2 | Every Deepgram/OpenAI content entry point honours consent | macOS + iOS, miniti | planned |
| R3 | Cloud work is fenced by account and generation | macOS + iOS, miniti | planned |
| R4 | Watch imports defer retries without spinning or starving other jobs | iOS, miniti | planned |
| R5 | Webhook coalescing cannot lose an update in flight | macOS + iOS, miniti | planned |
| R6 | Manual retry of a failed webhook has a valid payload | macOS + iOS, miniti | planned |
| R7 | History insight responses cannot overwrite a newer transcript/template | macOS + iOS, miniti | planned |
| R8 | Web/email confirmation link consumption is atomic | miniti-api | planned |
| U1 | Sending becomes a concise, grouped account of data destinations and current behavior | macOS + iOS, miniti | built 2026-10-27 for 3.4.0 build 139 (account-sending-consent-ux-plan.md), QA open |
| U2 | Shorter Deepgram/OpenAI consent with visible, accessible actions | macOS + iOS, miniti | built 2026-10-27 for 3.4.0 build 139 (account-sending-consent-ux-plan.md), QA open |

## Evidence and implementation contract

### R1: private mode during recording

`PrivateModeToggle` currently allows a change during recording. `setPrivateMode` changes preferences and presentation, while `startRecording` chooses `sessionTranscribesOnDevice` once and the running Deepgram socket remains unchanged. Sending can therefore claim a cloud session is local.

Use the small, explicit fix: disallow turning private mode on or off during recording, starting, resuming and transcript finalization. Enforce the rule in `AppState.setPrivateMode` as well as disabling the UI. Explain that the person must stop the recording first; do not silently change capture engines or interrupt the recording. Derive live Sending statements from the latched session engine, rather than a preference that applies to the next session. Keep configured webhook/CRM exports permitted; replace absolute "nothing leaves" wording with the actual AI-processing and export distinction.

Tests: cloud recording rejects enable; private recording rejects disable; pending start/grant cannot race the preference change; after stop/finalization the transition succeeds and the next start uses the intended engine; queued user-configured exports are unchanged. Device QA: compare actual Deepgram connection/counters with the live label before and after a stopped-session transition.

### R2: shared permission checks

Recording checks `hasAcceptedTerms`, but `generateInsightsForMeeting` and Watch import do not. History's Update action remains available after withdrawal. Audit the other content-bearing entry points: final/background insights, speaker naming, templates and template drafts, catch-up, investigations, Playbook and the classifier. Apply the consent contract consistently without turning private-mode checks into a substitute for consent.

Introduce one testable AppState policy for initiating external AI content work. Check it in real actions and at queued dispatch, not only in views. Denied actions show the existing permission flow or a clear blocked state. A Watch recording stays safely in the inbox until consent is granted; do not mark it done, delete its audio or repeatedly retry. Re-check after preparatory awaits and before starting a further network operation. Define the withdrawal boundary honestly: bytes already transmitted cannot be recalled; cancel owned work where possible and start no subsequent AI request after withdrawal. Local reading, import, coaching and deliberate user exports remain available. Enrollment, usage and version checks are not AI-content consent operations.

Tests through AppState: withdraw then regenerate saved summary/questions/template, draft a template, request a lookup/investigation, or resume queued finalization: no AI-content request. Watch arrival with consent unanswered or declined: audio preserved, no grant/upload/insights; granting consent resumes once. A withdrawal between grant preparation and upload prevents upload. Existing allowed paths still work. Keep tests off the installed account and its store.

### R3: cloud account/generation fence

Reproduced with the production `CloudSyncEngine` and a fake transport: switch A to B while A's `changes` request is outstanding; the old response inserts A's meeting and writes A's sequence under B. `resetBookkeeping` clears existing state but does not invalidate the pass. This is separate from the fixed idle restore bookkeeping bug.

Capture a context containing account ID and a monotonically changing generation for each pass. Invalidate it on account/credential replacement, sign-out, revoke, explicit reset and other transitions that discard the pass's authority. Compare it after every await, before applying responses/errors/cursors and before initiating another request, including conflict retries, tombstones, manifests and batch fetches. An A-to-B-to-A transition must still invalidate A's first pass. Scope cursor writes to the captured account only while that context remains valid. A stale pass must not clear a newer `needsReconcile`, mark new work synced, or pause the new account because the old request returned revoked/not-Pro. Cancellation is an optimization, not the correctness mechanism.

Tests with suspended fake-transport continuations: account switch during pull/manifest/put/delete/status; stale success, tombstone and error responses; A-B-A; same-account credential replacement/reset; new account reconciliation starts after the stale pass exits. Assert models, per-account cursors, pending deletions and UI state, not merely network counts. The broader B4 decision about carrying local meetings between accounts remains unchanged.

### R4: Watch retry scheduling

`WatchImportService.kick` selects both queued and waiting-for-minutes jobs, then calls itself after every run. `retryLater` sets queued, so an offline failure immediately retries; exhausted minutes repeatedly request grants until another refusal can turn the job into failed.

Persist retry eligibility (attempt count and next eligible time, with backward-compatible ledger decoding). Use bounded backoff for transient failures; network recovery or activation can trigger an eligibility check, not bypass the delay unconditionally. Waiting-for-minutes is blocked until an entitlement/usage change or explicit retry. Continue eligible independent jobs instead of selecting the same blocked first job. Coalesce timer/activation/file-arrival/manual triggers into one worker. Keep audio, receipts and the existing saved-meeting duplicate guard intact; avoid spinning in the background. R2's permission block is a separate reason to wait.

Tests: offline immediate failure makes one attempt until eligible; persistent limit makes no loop; a blocked first job does not starve a runnable second; relaunch preserves eligibility; simultaneous triggers run one job; manual retry is bounded; no duplicate meeting or duplicated session-end charge after recovery. Exercise the actual importer with injected clock, grant/transcription transport and receipts. Real iPhone QA includes airplane mode, exhausted minutes, relaunch and foreground/background transitions.

### R5: coalescing an in-flight webhook

Reproduced with production `DeliveryOutbox`: v1 is being sent, enqueue v2 under the same item ID, v1 succeeds, `apply` removes the item and v2 never goes out.

Give each payload revision its own completion identity, or keep one immutable in-flight item plus one coalesced successor. A completion can settle only the revision it sent. Newer content must survive successes, retries and terminal failures of the older revision. Preserve stable delivery IDs for retries of identical content; new content must not accidentally be deduplicated as the old payload by receivers. Persist the successor before considering it accepted. Deletion/discard must not resurrect it.

Tests with a suspended sender: enqueue v2/v3 during v1; v1 delivered/retry/rejected; persist/reload; deletion while outstanding; changed destination under the existing routing policy. Assert payloads delivered, not only queue length.

### R6: useful manual webhook retry

Terminal failures intentionally discard the transcript body. `retryNow` makes the item pending without rebuilding it, so the production sender rejects it as "missing body". The old test replaces that sender with one that accepts any item and misses the failure.

Keep terminal payload disposal. Make the UI action explicitly resend the current saved meeting: fetch it safely, encode its current permitted payload and create a new delivery identity. Do not resurrect trimmed text or a deleted meeting, and do not claim to replay a historical body that no longer exists. If the meeting or destination is unavailable, explain why and leave discard available. Define the event used for this current-state resend and cover receiver compatibility. CRM retries keep rebuilding from saved data. Implement after R5 so resends cannot be lost through coalescing.

Tests using the production sender's body requirements: terminal 4xx and retry exhaustion, resend succeeds with a nonempty current payload, edited/trimmed meeting, deleted meeting, removed endpoint, encoding/save failure, reload, and unchanged CRM retry. Never retain transcripts indefinitely to make the test pass.

### R7: History responses belong to the request's revision

`generateInsightsForMeeting` captures the transcript but checks only deletion before applying an answer; trim remains available during generation. A late answer can restore insights based on removed text and mark them current. Final-insight generation already captures `transcriptRevision`.

Capture meeting ID, transcript revision, requested mode, relevant template identity and request generation. Validate before any model write, freshness stamp, markdown export or webhook. A superseded/deleted/trimmed request is discarded without clearing a newer request's loading state. Apply the same discipline to saved-meeting topic/template paths that can race an edit. Preserve the existing user-wins rule for manual speaker edits.

Tests: delayed summary/questions/Sales/template response followed by trim, correction, undo, template change, deletion or a newer request. No stale data/freshness/export; unchanged revision applies normally. Use a real in-memory meeting and delayed service response.

### R8: atomic single-use link consumption

Reproduced from production `loginLinks.ts`: two concurrent `consumeLoginLink` calls both return success because lookup and unconditional update are separate operations.

Add a store operation that atomically claims an unconsumed, unexpired row of the expected purpose and returns it, using conditional `UPDATE ... RETURNING` in Postgres. Only that winner can issue the web session or perform email confirmation. Match semantics in the in-memory store and check expiry/purpose at consumption time. Preserve non-consuming approval-page previews and existing public unknown/expired/consumed responses without exposing account existence. Inspect every caller of the generic consume helper.

Do not blindly replace device-enrollment's inspect/bind/consume sequence: its Redis binding and Postgres link are separate stores, and lost-response recovery must remain possible for the same proven installation. Any change there needs an explicit recoverable claim/result contract and its own scenarios; the bounded fix here covers the generic web sign-in/confirmation consumption race. Tests: concurrent claims yield one winner/session, wrong purpose, expiry at the boundary, consumed link and confirmation failure. Run a real isolated Postgres concurrency test as well as the fake store test.

## User experience additions, approved 2026-10-26

U1 and U2 were pulled into 3.4.0 (build 139) on 2026-10-26; the implementation plan, file list, tests and QA lines are in [account-sending-consent-ux-plan.md](account-sending-consent-ux-plan.md). The R-series items below stay future work.

U1 and U2 ship in 3.4.0 build 139; the 137 and 138 builds and their QA results are superseded and the A5 QA is repeated on 139. B6a in the enrollment plan owns email/account/billing UX; do not implement a second account state machine here.

### U1: Sending is readable at a glance

**Evidence:** Ian finds the current tab poorly organized. `DataFlowRowsView` in `Miniti/Models/DataFlowSummary.swift` renders a flat list of provider paragraphs, a “sends/nothing” label and several Change links per row. macOS wraps that in one grouped Form section; iOS disables the jump buttons. Boolean `sends` describes eligibility/preferences, not live traffic. R1 already identifies a mismatch between private-mode preferences and a running cloud transcription session.

**Information hierarchy:** one compact summary of this recording while recording, otherwise “Based on your current settings”. State that this is a routing summary, not a network activity monitor. Below it use three stable, purposeful groups:

1. **Transcription and AI:** Deepgram, OpenAI, optional TypeSafe/Jev and configured Playbook search destination. Each row names recipient, a short description of data and purpose, and an accurate state.
2. **Sync and exports:** miniti cloud meeting copies and configured webhook/CRM destinations. Identify which sends run automatically and which require an explicit action. Keep deliberate exports allowed in private mode.
3. **Account and connections:** miniti account/usage/version traffic, diagnostics and calendar access. Distinguish fetching calendar events from writing them, and service metadata from meeting content. Describe backend mediation where it actually occurs.

Each row has a short title, one readable line (wrapping when needed) for the essential data/purpose, a neutral textual status, and **one** clear Configure action to the owning setting. Longer payload/retention explanations and secondary settings can expand under Details. Do not put five horizontally packed links under each provider, hide essential recipients behind disclosure, or repeat the same permission/private-mode paragraph in every row. Keep configured active destinations visible. Put unconfigured/disabled optional features under a compact “Not in use” disclosure, with counts and a reason available on expansion; Deepgram/OpenAI remain easy to find even when off. Do not reorder rows continually as traffic starts/stops.

Use status words that match the evidence: “Used for recordings”, “On request”, “Automatic export”, “Off”, “Paused” or “Not connected”, rather than claiming “Sending now” from a preference. The live summary uses the latched session engine and actual active session/mode, including local-model fallback; upcoming-session preferences cannot overwrite it. Saved/Watch processing and queued exports must not be described as absent solely because no live recording exists. The summary is not a claim that every configured operation has succeeded.

**Visual contract:** use existing `MinitiDesignSystem` tokens, native section spacing and thin dividers, with a consistent title/detail/status alignment. Avoid a wall of boxed cards, repeated colored dots, tiny caption paragraphs or competing accent links. Main text remains readable at the normal Settings scale. A narrow window/iPhone stacks status/action under the title; text never truncates horizontally. No new provider-colored button system. Match the information order across Mac, iPhone and iPad; provide real navigation to the owning setting on iOS rather than a sentence naming a tab. Native buttons retain focus and individual VoiceOver actions; do not combine a whole row in a way that hides Configure/Details controls. Respect Reduce Motion.

**Truthful copy:** remove “nothing leaves”, “nothing about your meetings” and blanket “nothing is stored” claims where exports, optional integrations, on-device Watch audio or provider-specific retention make them inaccurate. State verified behavior and link to fuller privacy information where needed; do not invent retention or training promises. Deepgram audio goes directly from the app to Deepgram (managed mode supplies a token); managed OpenAI text passes through miniti. Explain those paths separately rather than saying all managed audio/text traverses miniti. Keep local voice prints distinguished from exported speaker names/emails. Private mode remains the user-control contract agreed above.

**Validation:** retain and extend the pure summary tests for managed/BYOK, consent unanswered/declined, local transcription/fallback, private mode with a configured webhook/CRM, cloud on/off/paused, calendar, diagnostics and live vs next-session routing. Assert state text/payload facts, not just row counts. U1 must not advertise R1/R2 as fixed before they are. Render real-app previews/captures at the minimum supported Mac Settings size, normal desktop size, compact iPhone, iPad and large text. Check long hostnames and localized copy wrap, collapsed details retain essential information, keyboard/VoiceOver reach all actions, and each Configure link opens the correct section. Have Ian review the rendered layout before treating the redesign as complete.

### U2: concise consent with actions always reachable

**Evidence:** on a new Mac Ian had to scroll to find Allow/Not now. `TermsAcceptanceView` currently places a large logo, several paragraphs, links and both actions in a single ScrollView with 40-point vertical padding. Shortening copy alone does not guarantee button access.

**Layout:** a compact title/introduction, two short provider rows and a concise explanation of the choice. Put **Allow** and **Not now** (or **Cancel** for an existing-app sheet) in a persistent action area outside the scrollable disclosure body, respecting safe areas and window resizing. Reduce decorative branding/empty vertical space before reducing text size. At ordinary text size in the smallest supported Mac window, the essential disclosure and both actions should fit without scrolling. With larger accessibility text, the disclosure may scroll but the action area remains visible and cannot cover content. On compact widths use a vertical button stack if needed; preserve usable hit targets and native keyboard/focus behavior. No scroll-to-enable requirement or implied consent.

**Draft copy direction, to check against actual routing before implementation:**

> **Use cloud transcription and AI?**
>
> **Deepgram** receives audio, meeting titles and attendee names to transcribe your meetings.
>
> **OpenAI** receives transcripts, notes, meeting titles and attendee names for summaries and insights.
>
> With the managed plan, AI text requests pass through miniti. Audio goes directly to Deepgram. With your own keys, requests go directly to the providers.
>
> You can choose Not now and still read, import and export meetings. Change your choice in Settings, Privacy.

Keep the actual data categories and processing purposes visible, not only behind a policy link. Include concise Privacy policy / Terms links, with optional further detail for platform-specific local transcription and storage facts. Do not claim permission is an all-network switch, that every feature waits for recording to start, that private mode blocks deliberate exports, or that all audio is never stored (Watch/import paths differ). Make the difference between declining and granting clear without repeating it in several paragraphs. Other opt-in services retain their own disclosure/controls; this screen is not blanket approval for unrelated destinations. Preserve affirmative consent and the existing decline/cancel semantics.

**Consent-version rule:** a visual/wording simplification that preserves the existing disclosure does not automatically force every existing user through onboarding again. If the implementation changes recipients, data, purposes or permission meaning, apply the existing material-change version rule deliberately and document it. Existing acceptance/decline and account state must survive a pure layout update. Correctness of all content dispatch remains R2's work; ship accurate claims together with those guards rather than hiding a gap with shorter text.

**Validation:** first launch and in-app permission sheet on macOS/iPhone/iPad; normal and smallest supported windows, macOS display scaling, large text, VoiceOver, keyboard navigation and Reduce Motion. Assert both actions are initially visible and operable, links remain reachable, body content is not obscured by the footer, Allow records consent once, Not now remains a real route into the app, Cancel does not overwrite prior consent, and no AI-content request is triggered merely by presenting the screen. Capture the real new-Mac first-run layout that originally required scrolling; do not accept a large preview screenshot as sufficient. Pair with R2 real-action tests for History/Watch and other dispatch paths.

## Sequencing, compatibility and completion

1. R1/R2 establish permission behavior; R3 fences account work. R4 then uses the same permission policy.
2. R5 precedes R6; R7 and the backend-only R8 can proceed independently. U1 uses the routing correctness from R1/R2; U2 preserves consent semantics and ships its claims against R2's guards. B6a has its own email-route/state prerequisites and can precede ownership migration; B6b first-use changes wait for A4.
3. Existing credentials, accounts, meeting IDs and subscription ownership stay intact. No forced sign-out, data reset, compulsory email, quota reset or account merge. Persisted outbox/inbox changes must decode existing files. No Track B migration is smuggled into this batch.
4. Each slice gets its failing regression before the fix, then relevant shared tests and both full Apple bundles on the combined tree. Backend changes get route/store tests, typecheck and lint. Do not run tests against live accounts or real webhook recipients. Maintain same-day Linux contract tracking when an API contract changes.
5. Record actual commit, tested build, platform, result and outstanding device QA before changing a status row. A successful build, notarization or local install is not a release. Roll back code without deleting user stores; design additive ledger fields so the previous reader can still open them, and document retry/deduplication effects before rollout.

The 3.4.0 plan records Mac build 137 / iPhone build 138 QA completed on macOS 27 and iPhone, with macOS 26 explicitly unmeasured and waived by Ian for this release. These findings remain known risks until their slices are implemented; passing current QA does not close them. This document authorizes future implementation planning, not a push, deploy or release.

## Related enrollment incident follow-ups

Keep the evening incident in the enrollment plan. A4 owns the signed-out/revoked choice and suppression of silent creation; B1 owns subscription continuity; B6 owns visible identity and recovery methods. Rate-limit copy/handling and recognizable labels are linked there, with these constraints: no quota exemption based only on a device UUID; a free/different account alone does not explain an unsent email; iOS user-assigned names require Apple's entitlement or a deliberate user-entered label. These are not prerequisites for unrelated R slices and are not already implemented by 3.4.0.

## Small operator-copy correction

The documentation reconciliation found `probePolarConfig`'s success summary still says the product is known, although the revised probe validates product UUID shape only and reads subscriptions by organisation. In the next backend maintenance update, make the success text describe exactly those checks, with a regression test for the summary. Do not add an activation probe or claim product ownership was verified. This is copy accuracy alongside the eight behavioral slices and U1/U2, not another auth migration.
