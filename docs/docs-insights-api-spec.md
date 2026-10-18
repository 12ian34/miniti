# Docs Insights — miniti-api spec

Backend contract for the v1.27.0 **Docs insights** feature (topic list + per-topic
lookup). The macOS/iOS client is already implemented against this contract and
ships **tolerant of every field below being absent** — so nothing here breaks
existing clients, and the feature simply lights up in managed mode once these land.

This spec is written from the client's actual wire behaviour. Client references:
`Miniti/Services/MinitiAPIService.swift`, `Miniti/Services/DocsMCPService.swift`,
`Miniti/Services/InsightsService.swift`.

## Summary of work

1. **New** `mode: "docs_topics"` on `POST /api/insights` — extract lookup-worthy
   topic labels from a transcript. Free, **not** quota-metered.
2. **Extend** `mode: "docs"` on `POST /api/insights` — accept an optional `topic`
   field and use it as the docs search query. Each call is **one metered lookup**.
3. **Extend** `GET /api/usage` — add `docs_lookups_used` / `docs_lookups_limit`.
4. **Meter** docs lookups server-side: monthly allowance for managed-free
   (default **10/mo**), unlimited for Pro; enforce with `402` at the limit.

BYOK clients never call the backend for docs (they hit the MCP server + their own
LLM directly), so this is managed-mode only.

---

## Common request envelope

All calls reuse the existing `POST /api/insights` endpoint and auth.

- **Base URL:** `https://api.miniti.app/api` (client appends the path, so full URL is `…/api/insights`).
- **Method:** `POST`, `Content-Type: application/json`.
- **Headers (already sent on every request):**
  - `X-API-Key` — shared app secret (existing gate).
  - `X-Device-ID` — per-device identity; the metering + tier key.
  - `X-App-Version`, `X-Platform` (`ios` | `macos`).
- **Mode is selected by the `mode` field in the JSON body** (existing pattern:
  `standard`, `meddpicc`, `questions`, `catchup`, `speaker_names`, `docs`).

---

## 1. `mode: "docs_topics"` — topic extraction

Extract short, lookup-worthy product topics from the transcript. Pure LLM parse of
the transcript; **does not** hit the MCP server and **does not** consume quota.

### Request body

```json
{
  "mode": "docs_topics",
  "transcript": "<full or recent transcript text>",
  "model": "gpt-5-mini-2025-08-07",
  "language": "en",
  "docs_mcp_url": "https://docs.example.com/mcp"
}
```

- `transcript` — plain text. May be long; treat it like other insights modes
  (the client sends up to the full transcript).
- `model` — pinned client model id (`gpt-5-mini-2025-08-07`). Managed mode
  ignores this field for selection: `docs_topics` uses `gpt-5-mini-2025-08-07`
  and grounded `docs` answers use `gpt-5.4-mini-2026-03-17`. BYOK uses the
  client value directly.
- `language` — BCP-ish code (`en`, `de`, …). Topic strings must be in this
  language; JSON keys stay English.
- `docs_mcp_url` — sent for consistency/validation; **not required** for
  extraction. May be used to bias topics toward what the docs likely cover, but
  don't block extraction on it.

### Response `200`

```json
{
  "topics": ["SSO / SAML support", "data retention limits", "API rate limits"],
  "meta": { "degraded": false }
}
```

- `topics` — array of short strings (2–6 words each). The client dedupes (by a
  lowercased, whitespace-collapsed slug) and caps at 6, but the backend **should
  also** cap at ~6 and skip smalltalk/pricing/scheduling.
- `meta` — optional, same shape as other modes (see [Meta](#meta-object)). Omit or
  `degraded:false` on success.
- Empty transcript / nothing lookup-worthy → `{ "topics": [] }` (200, not an error).

### Extraction guidance (mirror the client's BYOK prompt for parity)

System: *"You extract concrete, lookup-worthy product topics from a live sales
conversation. A good topic is a specific subject or question the prospect raised
that product documentation could answer (e.g. 'SSO / SAML support', 'data
retention limits', 'API rate limits'). Never invent topics not grounded in the
transcript."*

Rules: each topic a short noun phrase or question (2–6 words); prefer things the
prospect asked or that need a factual product answer; skip smalltalk, pricing
negotiation, scheduling; max 6, most important first; empty array if nothing yet.
Return strict JSON `{ "topics": [...] }`.

### Errors

- Unknown-mode fallback: an older/partial deployment that doesn't recognise
  `docs_topics` **must not 500**. Returning any body without a `topics` array
  decodes client-side to `[]` and no-ops. Prefer returning `{ "topics": [] }`.
- Auth/device errors behave as today (`403 device_disabled`, etc.).

---

## 2. `mode: "docs"` — single-topic lookup (extend existing)

The bulk `mode: "docs"` handler already exists (retrieve chunks from
`docs_mcp_url`, ground an answer). Change: **accept an optional `topic`** and use it
as the MCP search query for a focused, single-topic answer. **Each call is one
metered lookup** (see [Quota](#quota--metering)).

### Request body

```json
{
  "mode": "docs",
  "transcript": "<transcript text, context/grounding>",
  "topic": "SSO / SAML support",
  "docs_mcp_url": "https://docs.example.com/mcp",
  "model": "gpt-5-mini-2025-08-07",
  "language": "en",
  "request_seq": 42
}
```

- `topic` — **new, optional.** When present, use it as the MCP search query
  (instead of deriving a query from the transcript). The grounded answer should be
  about this topic; echo it back as the card's `topic`. When **absent**, keep the
  existing transcript-derived behaviour (back-compat).
- `request_seq` — optional monotonic int; echo in `meta.request_seq` if you
  already do so for other modes.
- Other fields as today.

### Response `200`

```json
{
  "docs": [
    {
      "topic": "SSO / SAML support",
      "answer": "Miniti supports SAML SSO via Okta and Azure AD… (2–4 sentences).",
      "citations": [
        { "title": "SSO setup", "url": "https://docs.example.com/sso", "snippet": "Configure a SAML app…" }
      ],
      "priority": "high"
    }
  ],
  "meta": { "degraded": false, "request_seq": 42 }
}
```

- `docs` — array of cards ([DocPlaybookCard](#docplaybookcard-object)). For a
  single-topic request, **0 or 1** cards:
  - **1 card** when the docs cover the topic. Every card **must** have ≥1 citation
    with a `title`; `url` may be `null` only if the chunk had no URL. (The client
    drops any card with zero citations.)
  - **0 cards** (`"docs": []`) when the docs don't cover the topic → client shows
    "no docs match this topic". Still counts as a used lookup (a lookup was
    performed).
- `meta.degraded: true` — signals a transient failure (MCP timeout, model
  overload). The client keeps the topic `pending` and surfaces "docs service is
  busy". **Do not** meter a degraded response as a used lookup.

### Grounding guidance (mirror client BYOK `generateDocsCard`)

System: *"You are a technical sales engineer copilot. Answer only from the provided
documentation chunks. Never invent product facts. The card must include citations
drawn from those chunks."* Answer 2–4 sentences, concrete, speakable on a call;
`priority: "high"` only if the prospect clearly asked this; if chunks don't cover
the topic return `{ "docs": [] }`.

---

## 3. `GET /api/usage` — add docs-lookup counters

The client already polls `GET /api/usage` and decodes `UsageInfo`. Add two fields
(snake_case canonical; camelCase also accepted; string or number both fine — the
client tolerates all).

```json
{
  "minutes_used": 123.4,
  "minutes_limit": 500,
  "resets_at": "2026-08-01T00:00:00Z",
  "tier": "free",
  "subscription_status": "active",

  "docs_lookups_used": 3,
  "docs_lookups_limit": 10
}
```

- `docs_lookups_used` — lookups consumed this period.
- `docs_lookups_limit` — monthly allowance for the tier.
- **Absent → client treats docs lookups as unmetered** (no gating). So only emit
  these for tiers you actually meter (managed-free). For Pro you may omit them or
  send an effectively-unlimited limit; the client also independently treats
  `tier == "pro"` as unmetered.
- Same reset boundary as minutes (`resets_at`).

---

## Quota & metering

| Tier | Docs lookups | Enforced by |
|---|---|---|
| Managed **free** | **10 / month** (default; make it config) | server-side counter |
| Managed **Pro** | unlimited | — |
| BYOK | unlimited, never hits backend | — |

- **Count a lookup** = one `mode: "docs"` request that actually performs a
  retrieval+grounding (both a card and a `docs: []` no-match count). **Do not
  count** `degraded` responses or requests rejected before retrieval.
- **Do not count** `mode: "docs_topics"` — topic extraction is free.
- Store the counter on the same rail as minutes, keyed by `X-Device-ID` (or the
  account behind it), with the same monthly reset.
- **At the limit**, reject `mode: "docs"` with **`402`** and an `APIError` body:

  ```json
  { "error": "docs_limit_reached", "message": "Monthly docs lookups exhausted", "resets_at": "2026-08-01T00:00:00Z" }
  ```

  The client's `validateResponse` already maps `402` → a limit-reached error and
  the docs UI surfaces the upgrade prompt. (It also gates the button client-side
  from `docs_lookups_remaining = limit − used`, so `402` is the backstop.)
- Pro is identified as today (Polar entitlement → `tier: "pro"`). **Polar is not
  involved in metering** — it only sets the tier.

---

## Data types

### DocPlaybookCard object

| field | type | notes |
|---|---|---|
| `topic` | string (required) | echo the request `topic`; client uses it as the card id/label |
| `answer` | string (required) | 2–4 sentences, grounded |
| `citations` | array (required, ≥1) | see below; card dropped client-side if empty |
| `priority` | string? | `"high"` or `"normal"` (default) |

### DocCitation object

| field | type | notes |
|---|---|---|
| `title` | string (required) | falls back to "Documentation" client-side if missing |
| `url` | string? | http/https only; other schemes are not rendered as links |
| `snippet` | string? | short quote |

### Meta object

Same struct as existing insights modes:

| field | type | notes |
|---|---|---|
| `degraded` | bool | default false; true = transient failure, keep prior state, don't meter |
| `fallback_reason` | string? | optional |
| `request_seq` | int? | echo of request's `request_seq` |

---

## MCP retrieval notes

- Reuse the existing docs-MCP path (`miniti-api/lib/mcpClient.ts`, `docsMcp.ts`)
  that already backs bulk `mode: "docs"`. The only change is **query source**:
  when `topic` is present, search with the topic string; otherwise keep the
  transcript-derived query.
- Keep the existing **SSRF protections** on `docs_mcp_url` (the client mirrors
  them in `DocsMCPService.validateMCPURL`: https-only, block localhost/`.local`/
  `.internal`/metadata hosts and private IPv4/IPv6 ranges, refuse redirects, cap
  response size). Re-validate server-side regardless of client.
- Tool discovery / chunk normalization already exist for bulk mode; unchanged.

---

## Rollout & back-compat

- All three changes are **additive**. Ship in any order; the client degrades:
  - No `docs_topics` support → empty topic list, feature simply shows nothing in
    managed mode (BYOK still works).
  - `topic` ignored on `mode: "docs"` → falls back to transcript-wide answer
    (older behaviour); still functional.
  - No usage fields → docs lookups treated as unmetered.
- Recommended order: (1) usage fields + counter, (2) `docs` `topic` support +
  metering, (3) `docs_topics`.

## Acceptance checklist

- [ ] `mode: "docs_topics"` returns `{ "topics": [...] }`, ≤6, language-correct,
      empty array when nothing lookup-worthy; never 500 on unknown mode.
- [ ] `mode: "docs"` with `topic` searches by that topic and returns 0/1 cards,
      each with ≥1 citation; `topic` absent still works (back-compat).
- [ ] `docs_topics` does not decrement the counter; a real `docs` lookup does; a
      `degraded` docs response does not.
- [ ] Managed-free blocked at 10/mo with `402 docs_limit_reached`; Pro unlimited.
- [ ] `GET /api/usage` returns `docs_lookups_used` / `docs_lookups_limit` for
      metered tiers; resets with minutes.
- [ ] `docs_mcp_url` re-validated server-side (SSRF) on every docs/​topics call.
