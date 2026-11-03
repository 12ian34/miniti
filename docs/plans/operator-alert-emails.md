# Clearer operator alert emails, 3.7.0

Selected by Ian on 2026-11-03 after an OpenAI alert was difficult to understand and overstated its evidence. Implemented locally in the backend; verification is in progress, with no deployment or production mail. The [roadmap](../roadmap.md#selected-next-release-370) owns priority. Ian reconfirmed that this complete plan remains in 3.7.0 alongside model retirement. Backend deployment may precede the apps once validated; that sequencing does not defer the wider email fixes beyond 3.7.0. No app payload or Linux binary change is needed for this work.

## Confirmed problems

- `miniti-api/lib/opsHealth.ts` probes each model separately, but `probeOpenAI` replaces the individual error details with summary lines. The provider's bounded error message is lost before storage and email, leaving `HTTP 400 invalid_request_error` without an explanation.
- `CHECK_COPY.openai` claims every managed user's summaries, action items, Questions, Sales and speaker names stop. A failed synthetic probe does not prove customer failures. Current normal routing splits tasks between Luna and GPT-5.4 mini, so a refusal for one model does not establish failure of the other routes.
- Every OpenAI alert links to billing, even for an invalid request. Multiple results are joined with slashes into one dense paragraph. Recovery subjects append "is resolved" to failure titles rather than describing what recovered.
- Other operator templates also overstate evidence: client-error counts imply everyone is affected, and Deepgram/KV copy overlooks actual engine/mode boundaries. Incident emails preserve useful distinctions but bury the action beneath timestamps and technical qualifiers.

Observed 2026-11-03: Ian's pasted alert shows GPT-5.4 mini refusing one probe while GPT-5 mini and Luna answered. Stored production state read later shows a recovery email at 00:45 and all three probes returning HTTP 200 at 08:45 Europe/London. The 24-hour server-error counter was zero, with incomplete diagnostic coverage. This does not establish the exact rejection reason, outage duration or number of affected customer requests. Do not invent the missing provider message or describe the incident as model retirement.

### Follow-up verification, 2026-11-03

Read-only logs reviewed at approximately 09:33 Europe/London establish the sampled times: the GPT-5.4 mini probe was rejected at **2026-11-02 23:45** with HTTP 400 `invalid_request_error`; the next hourly run at **2026-11-03 00:45** passed and sent recovery. The 22 retrieved hourly runs from 2026-11-02 11:45 through 2026-11-03 08:45 contain this one failed OpenAI check. The supplied alert identifies Luna and GPT-5 mini as healthy peers; stored state confirms all three healthy at 08:45. Missing provider detail prevents diagnosis of the rejection or its duration. Deepgram's 09:15 balance lookup and listen handshake passed; the stored server-error counter remains zero for 24 hours.

Separately, five client AI warnings occurred on 2026-11-02 between 12:47 and 15:51, hours before this probe. The 1,038 retrieved insights requests after the previous review all have successful server completion telemetry. Neither observation resolves the other. The [client diagnostic follow-up](recording-reliability-followup.md#7-backend-completion-does-not-explain-client-ai-failure) owns tracing those failures; do not present them as proven impact of the overnight probe.

## Selected fixes

### Preserve diagnostic evidence

Carry per-model status, error code/type, bounded sanitized provider message, parameter name and provider request ID where available through aggregation, stored state and the admin detail view. Keep absent values explicit. Limit lengths and strip secrets, credentials, request bodies and customer content; these probes use synthetic input. Escape HTML and unsafe link content. Retain a bounded last-failure snapshot and first/latest observed failure plus successful-check times so recovery does not erase the reason. Define caps/retention in the implementation; no unbounded incident archive.

An HTTP 400 is a rejected request, not proof of retirement, billing failure or a full outage. Distinguish invalid request, missing/inaccessible model, authentication, exhausted quota, rate limiting and inconclusive network/provider errors only where structured evidence supports it. Include the original bounded technical fields below the plain-language explanation. Preserve existing classification and notification thresholds unless a specific correction is separately justified; clearer copy must not hide failures or introduce extra probes.

Include a bounded probe-validity investigation: inspect the actual synthetic request's model-specific parameters and token budget, test structured rejection handling, and correct any demonstrated request-construction defect. Do not infer a customer outage or dismiss the HTTP 400 as a false alarm without evidence. If the lost provider message prevents reproduction, close the evidence-retention defect while leaving the historical cause unknown. No extra production probes or notification-threshold changes are selected.

### Use a consistent email structure

1. **Subject:** `miniti: [specific check/problem]` or `miniti: [specific check] recovered`. Name the affected feature/model in readable terms. Avoid "OpenAI is failing" and unexplained error codes as the whole subject.
2. **What happened:** one short sentence describing the observed result. Say "our automated check was rejected" when that is the evidence.
3. **Possible impact:** name only tasks using the affected model under the checked deployment's routing. Separate customer failures actually recorded from potential impact, and say when customer impact is unknown. A model used only for fallback must be labelled as such. Do not claim unaffected BYOK keys, local engines or other providers were tested.
4. **Other checks:** one compact line or list of relevant successful checks, explicitly described as check results rather than proof every feature works. Put full model IDs in technical details.
5. **What to do:** one specific next action with the relevant link. For a generic invalid request, inspect the check's request/error details. Billing links belong to quota/billing evidence; credentials links belong to authentication/access evidence. Unknown failures point to diagnostics, not a guessed fix.
6. **Timing:** last checked and first observed failure when retained, using `YYYY-MM-DD HH:mm Europe/London` with GMT/BST offset where useful. Say "first observed" rather than claiming continuous downtime between hourly samples. Put retry cadence in a short footer: "Checked hourly. Reminder after 6 hours if still failing. One email when the check recovers." Match actual policy per check.
7. **Technical details:** readable rows or separate lines for status, error code, provider explanation, exact model and request ID. Missing detail says "not retained" or "not provided", never a fabricated diagnosis.

Keep the primary explanation/action short enough to scan on a phone. Provide equivalent readable HTML and plain text. Use semantic headings/lists and a clear action link; no slash-separated result dumps or empty spacer tables in the message content. Inspect the shared renderer before changing it, and preserve unrelated sign-in/account email behavior. Do not assume the blank tables in the pasted message reproduce the original email layout.

### Scope and notification behavior

Apply this structure to existing operational health emails (OpenAI, Resend, Neon, KV, cron, spend, Polar and aggregate errors), Deepgram alerts and client-incident alerts. Keep account/sign-in emails, marketing messages and the weekly digest outside this change. Preserve incident evidence rules from the delivered [incident-alert plan](incident-alert-clarity.md): occurrence versus receipt time, historical versus current evidence, unknown attempt counts and audio recovery versus transcript completeness. Move secondary diagnostic qualifications into details without removing them.

Preserve hourly checks, existing severity/repeat/cooldown behavior, recipients, deduplication and recovery state. No extra notification channel, forced cron run, production mail send or alert-state reset is needed for development. Recovery must say which check now passes, and when; it cannot claim failed summaries were regenerated, missing transcript recovered or every customer recovered. Shared OpenAI key refusal is evidence about that key; a model-specific provider problem could also affect BYOK, which these checks do not observe.

## Proposed copy for the reported alert

Illustrative rewrite using only the supplied alert evidence, not a new email or a claim about current state. Populate the check time from stored state when available.

**Subject: miniti: GPT-5.4 mini health check rejected**

Our automated check of GPT-5.4 mini was rejected by OpenAI. The check cannot confirm that model is available.

**Possible impact:** Questions, Sales, filled meeting templates, Playbook answers and investigations may be affected for managed users. Customer failures have not been confirmed from this check.

**Other checks:** Luna passed. It handles managed summaries, action items and speaker names. GPT-5 mini also passed. BYOK requests were not checked.

**What to do:** Open the OpenAI check in the miniti admin dashboard and inspect the rejection details. This alert does not identify a billing problem.

**Technical details:** HTTP 400; `invalid_request_error`; model `gpt-5.4-mini-2026-03-17`. The provider's explanation was not retained by the current monitor, so the exact cause is unknown.

Checked hourly. Reminder after 6 hours if still failing. One email when the check recovers.

Recovery subject: **miniti: GPT-5.4 mini health check recovered**. Body: "The GPT-5.4 mini check passed at [observed time]. All three model checks passed in this run. No action is needed for this alert." The model count comes from that run; after retirement there are two. Do not insert unobserved timestamps or infer the full failure duration.

## Acceptance and delivery

- Reproduce single-model HTTP 400 with healthy peers using fixtures; verify retained parameter/error evidence and model-appropriate probe construction. Distinguish a rejected probe, independently recorded client failures and successful client application without claiming continuous downtime between hourly observations.
- Fixture tests exercise single-model rejection with healthy peers, all-model key/quota failures, fallback-only failure, unknown network results, rate limits, absent/malformed error bodies and recovery. Assert affected-task mapping follows the central routing configuration including rollback switches, not a second stale hardcoded map.
- Test code/message/parameter/request-ID retention through aggregation, persistence and admin/email output; old stored states still decode. Verify bounds, redaction, HTML escaping and no credentials/content in mail. Recovery retains bounded last-failure context without replaying notifications.
- Preview warning, critical, reminder, unknown and recovered examples for each existing email family in both formats. Verify subjects/actions match evidence; spend warnings do not claim broken service, missed jobs name the job, and incident counts do not become failed-meeting counts. Inspect desktop and narrow/mobile rendering and readable plain-text copy.
- Keep notification decision regressions passing, including six-hour repeats where applicable, unknown-hour escalation, no reset/re-alert storm on deployment, and existing filtered admin links. Choose a verified admin destination for each action; add an OpenAI-check deep link if none exists rather than inventing one in the mail.
- Run focused tests plus required backend suite/type/lint/build checks. Review saved previews without sending mail. Deploy through the backend's normal release process, record revision and one normal scheduled run, and update the operations runbook/current contracts. No app payload changes or retrospective editing of already-sent mail.

## Local implementation evidence, 2026-11-03

`opsHealth` retains sanitized per-model status/code/type/message/parameter/request ID and central-router task snapshots. Messages are capped at 400 characters, identifiers at 80–128, and last-failure context at 12 rows of 600 characters plus two model IDs. The single snapshot expires after 30 days on normal evaluation; notification state remains intact. First/latest observed failure and successful-check times are additive and older state still loads. Recovery keeps the failed model name and retained rejection detail. No extra probes or thresholds were introduced; the historical 400 cause remains unknown. The existing synthetic request uses 16 completion tokens and explicit model-specific reasoning; no parameter defect was demonstrated.

A read-only `/admin/health#openai` page displays the authenticated stored result without triggering checks. Operator-only semantic HTML now covers operational checks, Deepgram and client incidents; account/sign-in and digest rendering stay on their existing path. Evidence controls billing/access links and possible-impact wording. Existing cadence and incident regressions pass. Saved synthetic health examples live at `/tmp/miniti-370-email-previews` for this session; OpenAI critical HTML was visually inspected at 390px and 1100px widths with no clipping. Broader email-client compatibility and remaining family preview review are still release checks. No mail was sent outside the test transport.
