# Client Insights Reliability Implementation Plan

> This document is a complete spec for the Miniti macOS/iOS client changes needed to complement the backend insights reliability fixes. The backend has already been deployed with: `reasoning_effort: 'low'` on all OpenAI calls, fixed timeout tier selection, simplified token budgets, and rate limit bumped to 15/min. The client changes below complete the reliability overhaul.

## Context: What the backend already does

The backend (`/api/insights`) already supports everything the client needs:

- **`meta` in every response**: `{ applied: true, stale: false, degraded: bool, fallback_reason: string|null, request_seq: int|null }`
- **`request_seq` echo**: whatever the client sends as `request_seq` is echoed back in `meta.request_seq`
- **Incremental payloads**: `incremental: true` + `incremental_payload` with delta, recent, rolling state
- **Fallback preservation**: when degraded, backend preserves rolling state from the request's `incremental_payload` in the response
- **Two timeout profiles**: incremental requests (35s budget), full requests (56s budget) — selected by whether `incremental_payload` is present

The backend is fully backward compatible. Old clients keep working but benefit from faster responses (`reasoning_effort: 'low'`).

## Current client state (from `../miniti` codebase audit)

| Aspect | Current State | File |
|--------|--------------|------|
| Per-mode ack cursors | Already separate: `managedStandardAckedSegmentCount` / `managedMeddpiccAckedSegmentCount` | `AppState.swift` |
| Per-mode rolling state | Already separate summary contexts and segment counts | `AppState.swift` |
| Tab switching | Already UI-only, no request side effects | `AppState.swift` |
| `meta.degraded` | **Not decoded** — `ManagedInsightsResponse` has no `meta` property | `MinitiAPIService.swift` |
| `request_seq` | **Not used** anywhere | — |
| Scheduling | Segment thresholds: 3/8 (standard), 6/12+60s (MEDDPICC) | `AppState.swift` |
| Incremental cutover | At 15k chars transcript length | `AppState.swift` |
| `recent_transcript` window | 6k chars | `AppState.swift` |
| Warmup placeholder | No placeholder shown | — |

## Overview of changes

There are **8 changes** organized by priority. Changes 1-2 are critical (enable the no-loss protocol). Changes 3-8 are the scheduling/UX improvements.

---

## Change 1: Decode `meta` from response [CRITICAL]

**File**: `MinitiAPIService.swift`

**What**: Add a `Meta` struct to `ManagedInsightsResponse` and decode it from the response JSON.

The backend already sends this in every `/api/insights` response:
```json
{
  "summary": "...",
  "action_items": [...],
  "topics": [...],
  "discussion_flow": [...],
  "title": "...",
  "metrics": null,
  "economic_buyer": null,
  "decision_criteria": null,
  "decision_process": null,
  "paper_process": null,
  "identified_pain": null,
  "champion": null,
  "competition": null,
  "meta": {
    "applied": true,
    "stale": false,
    "degraded": false,
    "fallback_reason": null,
    "request_seq": 42
  }
}
```

Add to `ManagedInsightsResponse`:
```swift
struct Meta: Codable {
    let degraded: Bool
    let fallbackReason: String?
    let requestSeq: Int?

    enum CodingKeys: String, CodingKey {
        case degraded
        case fallbackReason = "fallback_reason"
        case requestSeq = "request_seq"
    }
}

// Add to ManagedInsightsResponse
let meta: Meta?
```

Decode with `decodeIfPresent` so older backend versions (without meta) don't break the client. When `meta` is nil, treat as non-degraded for backward compatibility.

---

## Change 2: Gate ack cursor on `meta.degraded` [CRITICAL]

**File**: `AppState.swift` — wherever the ack cursor is advanced after a successful insights response

**What**: Only advance the ack cursor and update rolling state when `meta.degraded != true`.

**Current behavior** (causes information loss):
```swift
// After receiving insights response:
managedStandardAckedSegmentCount = currentSegmentCount  // Always advances
// rolling state is updated with response data
```

**New behavior**:
```swift
// After receiving insights response:
let isDegraded = response.meta?.degraded ?? false

if !isDegraded {
    managedStandardAckedSegmentCount = currentSegmentCount
    // Update rolling state (summary, action_items, etc.) from response
    // Increment success count for this mode
} else {
    // Do NOT advance cursor
    // Do NOT update rolling state
    // The delta will naturally grow to include this window on the next request
}
```

Apply the same logic for MEDDPICC mode using `managedMeddpiccAckedSegmentCount`.

**Why this is critical**: Without this, the client advances past transcript that was never properly analyzed, causing the "short/repetitive insights" and "empty MEDDPICC" symptoms observed in production.

---

## Change 3: Per-mode `request_seq` counters

**File**: `AppState.swift`

**What**: Add two monotonic counters (one per mode) and include in each request. On response, reject stale responses.

```swift
private var standardRequestSeq: Int = 0
private var meddpiccRequestSeq: Int = 0
private var lastAppliedStandardSeq: Int = -1
private var lastAppliedMeddpiccSeq: Int = -1
```

When sending a request:
```swift
standardRequestSeq += 1
let seq = standardRequestSeq
// Include request_seq: seq in the request body
```

When receiving a response:
```swift
guard let responseSeq = response.meta?.requestSeq, responseSeq >= lastAppliedStandardSeq else {
    // Stale/out-of-order response — drop silently
    return
}
lastAppliedStandardSeq = responseSeq
// Apply response normally (subject to degraded check from Change 2)
```

---

## Change 4: Fixed 30s cadence scheduling

**File**: `AppState.swift`

**What**: Replace the current segment-threshold scheduling with fixed 30-second timers per mode, with a silence gate and staggered start.

**Current** (from `handleSpeakerSegments`):
- Standard: first at 3 segments, then every 8 segments
- MEDDPICC: first at 6 segments, then every 12 segments + 60s minimum interval

**New**:

### Warmup phase
- **Standard**: fire first request when 4 finalized segments exist
- **MEDDPICC**: fire first request when 6 finalized segments exist
- During warmup, send **full transcript** (`incremental: false`)
- Track `standardSuccessCount` and `meddpiccSuccessCount` (increment only on non-degraded responses)

### Steady-state phase (after 2 non-degraded successes per mode)
- **Standard**: fire every 30 seconds
- **MEDDPICC**: fire every 30 seconds, staggered ~15 seconds after Standard
- **Silence gate**: if no new finalized segments since the last request for that mode, skip the tick (don't waste API calls during silence)
- Send **incremental** requests (see Change 5)

### Implementation approach
Use `Timer` or `Task.sleep` based recurring workers. Each mode has its own cadence anchor timestamp that resets when:
- A request fires (scheduled or manual)
- The Update button is pressed

### Tab independence
MEDDPICC scheduling runs **regardless of which tab is active**. Tab switching does not start, stop, or re-trigger any request. (This already works correctly — don't break it.)

---

## Change 5: Success-count-based incremental cutover

**File**: `AppState.swift`

**What**: Replace the current 15k-char transcript length cutover with a success-count cutover.

**Current**:
```swift
guard fullTranscript.count > managedIncrementalCutoverChars else {
    // Send full transcript
}
```

**New**:
```swift
let successCount = (mode == .standard) ? standardSuccessCount : meddpiccSuccessCount
if successCount < 2 {
    // Warmup: send full transcript (incremental: false)
    // Use full transcript in the `transcript` field
    // Don't send incremental_payload
} else {
    // Steady state: send incremental
    // incremental: true
    // transcript: recent_transcript value (backend deduplicates)
    // incremental_payload: delta + recent + rolling_state
}
```

**Why**: The char-length cutover is fragile — a short meeting may never hit 15k chars and always send full, while a long meeting crosses the threshold at an unpredictable time. Success-count (2) ensures there's always a valid rolling state before switching to incremental.

---

## Change 6: Increase `recent_transcript` window to 10k chars

**File**: `AppState.swift` — wherever `managedIncrementalRecentWindowChars` is defined

**What**: Change from 6,000 to 10,000 chars.

This gives the model ~10 minutes of recent conversation context for incremental updates, improving quality without significant payload/latency impact (~1k extra input tokens, ~1-2s extra).

---

## Change 7: Update button fires both modes + resets cadence

**File**: `AppState.swift` — Update button handler

**What**: When the user presses Update on either tab:
1. Fire an immediate request for **Standard** mode
2. Fire an immediate request for **MEDDPICC** mode
3. Reset both cadence anchors (so the next tick is 30s from now)

Both requests should be incremental (rolling state + delta since last good ack) unless the delta exceeds ~35k chars, in which case send full.

---

## Change 8: Warmup placeholders

**File**: UI layer (wherever Standard/MEDDPICC tab content is rendered)

**What**: Before the first successful response for each mode, show placeholder text:
- Standard tab: **"no insights yet..."**
- MEDDPICC tab: **"no meddpicc yet..."**

Replace placeholder with real content after the first non-degraded response for that mode.

---

## Recovery: What happens when things go wrong

The incremental protocol handles failures **automatically** — no special recovery logic needed for most cases.

### Normal degradation (1-5 failed requests)
1. Response comes back with `meta.degraded: true`
2. Client does NOT advance ack cursor (Change 2)
3. Delta grows naturally: next request includes all transcript since last good ack
4. Rolling state stays as the last good state (what's displayed in the tab)
5. Next 30s tick sends the accumulated delta — model catches up

This is exactly "send what's in the tab + all transcript since the degradation."

### Extreme degradation (delta > 35k chars, ~35 min of unprocessed speech)
1. Client detects delta exceeds 35k chars
2. Next request sends **full transcript** (`incremental: false`) — backend gives this the generous 56s timeout
3. On success: reset ack cursor, resume incremental mode
4. On failure: wait for next 30s tick and try again

### Manual recovery
The Update button always fires immediately with both modes. This is the user's escape hatch.

---

## Request payload reference

### Full (warmup/catch-up) request
```json
{
  "transcript": "[Speaker 1] Full transcript text...",
  "mode": "standard",
  "request_seq": 5,
  "existing_summary": "Previous summary if available",
  "existing_title": "Existing title if available"
}
```

### Incremental (normal steady-state) request
```json
{
  "transcript": "[Speaker 2] Last ~10k chars of recent transcript...",
  "mode": "standard",
  "request_seq": 12,
  "existing_summary": "Current summary displayed in tab",
  "existing_title": "Current title",
  "incremental": true,
  "incremental_payload": {
    "strategy": "delta_recent_window_v1",
    "full_segment_count": 140,
    "acked_segment_count": 120,
    "delta_segment_count": 20,
    "recent_segment_count": 35,
    "transcript_delta": "[Speaker 1] New transcript since last successful ack...",
    "recent_transcript": "[Speaker 2] Last ~10k chars...",
    "rolling_state": {
      "summary": "Current summary from last good response",
      "discussion_flow": ["Point 1", "Point 2"],
      "action_items": ["Action 1"],
      "topics": ["Topic 1", "Topic 2"],
      "suggested_title": "Meeting Title"
    }
  }
}
```

For MEDDPICC mode, add `meddpicc` to `rolling_state`:
```json
{
  "rolling_state": {
    "summary": "...",
    "discussion_flow": [...],
    "action_items": [...],
    "topics": [...],
    "suggested_title": "...",
    "meddpicc": {
      "metrics": "Point one\nPoint two",
      "economic_buyer": null,
      "decision_criteria": "Criteria evidence",
      "decision_process": null,
      "paper_process": null,
      "identified_pain": "Pain description",
      "champion": null,
      "competition": null
    }
  }
}
```

### Response shape (unchanged)
```json
{
  "summary": "...",
  "action_items": ["..."],
  "topics": ["..."],
  "discussion_flow": ["..."],
  "title": "...",
  "metrics": null,
  "economic_buyer": null,
  "decision_criteria": null,
  "decision_process": null,
  "paper_process": null,
  "identified_pain": null,
  "champion": null,
  "competition": null,
  "meta": {
    "applied": true,
    "stale": false,
    "degraded": false,
    "fallback_reason": null,
    "request_seq": 12
  }
}
```

**Key fields to read from `meta`**:
- `degraded`: if `true`, do NOT advance ack cursor or update rolling state
- `request_seq`: use to detect stale/out-of-order responses
- `fallback_reason`: optional, useful for debug logging (values: `"empty_content"`, `"json_parse_failed"`, `"completion_retry_exhausted"`, `"transient_openai_failure"`)

---

## Testing checklist

1. **45-minute continuous talking run** — verify insights stay populated and grow over time for both Standard and MEDDPICC
2. **Fixed 30s cadence** — verify requests fire at ~30s intervals per mode (use debug logging)
3. **Silence gate** — verify a 2+ minute silence period produces no wasted requests
4. **Degraded response handling** — verify ack cursor does NOT advance on `meta.degraded: true` (simulate by checking next request's `acked_segment_count` stays the same)
5. **Update button** — verify it fires both modes immediately and resets the 30s timer
6. **MEDDPICC without tab** — verify MEDDPICC populates progressively even when Standard tab is active
7. **Tab switching** — verify switching tabs doesn't trigger, stop, or duplicate any requests
8. **Training tab** — verify it's completely unchanged
9. **Warmup placeholders** — verify "no insights yet..." and "no meddpicc yet..." show before first successful response
10. **Stale response rejection** — verify out-of-order responses (lower `request_seq`) are silently dropped
11. **Delta accumulation** — simulate 3+ degraded responses and verify the next request's `transcript_delta` includes all unprocessed segments

---

## Architecture diagram

```
┌──────────────────────────────────────────────────┐
│                     Client                        │
│                                                   │
│  ┌─────────────┐          ┌─────────────┐        │
│  │  Standard    │          │  MEDDPICC   │        │
│  │  Worker      │          │  Worker     │        │
│  │             │          │             │        │
│  │  ackCursor   │          │  ackCursor   │        │
│  │  rollingState│          │  rollingState│        │
│  │  successCount│          │  successCount│        │
│  │  requestSeq  │          │  requestSeq  │        │
│  │  cadence: 30s│          │  cadence: 30s│        │
│  └──────┬──────┘          └──────┬──────┘        │
│         │ (staggered ~15s)       │               │
│         ▼                        ▼               │
│  ┌──────────────────────────────────────┐        │
│  │        Silence Gate                   │        │
│  │  (skip if no new segments)            │        │
│  └──────────────┬───────────────────────┘        │
│                 │                                 │
│                 ▼                                 │
│  ┌──────────────────────────────────────┐        │
│  │   successCount < 2? → Full request    │        │
│  │   delta > 35k?      → Full request    │        │
│  │   otherwise          → Incremental    │        │
│  └──────────────┬───────────────────────┘        │
│                 │                                 │
└─────────────────┼─────────────────────────────────┘
                  │
                  ▼
    ┌─────────────────────────┐
    │  POST /api/insights     │
    │  (backend)              │
    │                         │
    │  reasoning_effort: low  │
    │  timeout: 35s or 56s    │
    │  token budget: flat     │
    └────────────┬────────────┘
                 │
                 ▼
    ┌─────────────────────────┐
    │  Response + meta        │
    │                         │
    │  meta.degraded?         │
    │  ├─ false → advance     │
    │  │   ack cursor,        │
    │  │   update state       │
    │  └─ true → do nothing,  │
    │     delta accumulates   │
    └─────────────────────────┘
```

---

## Priority order for implementation

1. **Change 1 + 2** (decode meta + gate ack cursor) — critical, deploy ASAP
2. **Change 3** (request_seq) — protects against stale responses
3. **Change 4** (30s cadence scheduling) — the main UX improvement
4. **Change 5** (success-count cutover) — cleaner incremental transition
5. **Change 6** (10k recent window) — minor quality improvement
6. **Change 7** (update button) — UX polish
7. **Change 8** (warmup placeholders) — UX polish

Changes 1-2 can be shipped independently as a quick win. Changes 3-8 can follow as a single update.
