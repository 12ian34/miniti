# Meeting search by people, title, date and keywords (2.11.0)

Field request, 2026-10-02 (Sasha): "search meetings is very limited… no search by people/date. meeting titles are mixed up as it auto changes them… basic search based on attributes: by people from calls from calendar, by title from the calendar events, by date, by text, simple keywords inside the transcription. Not semantic."

## What search does today

`MeetingSearchResult.search(query:in:)` (`Miniti/Models/Meeting.swift`) treats the whole query as one case-insensitive substring and scores title (100), topics (50), notes (40), summary (30), action items and discussion flow (25), MEDDPICC and template sections (20), transcript (10, queries of 3+ characters only), plus a recency boost. The same function serves the macOS sidebar (`MainWindow.swift`, debounced) and the iOS History tab (`HistoryView_iOS.swift`).

Gaps against the request:

- Two words such as `sasha pricing` never match unless they appear adjacent in that order.
- Attendees (`attendeesJSON`: email, display name, domain) and speaker names (`speakerNamesJSON`) are not searched at all.
- No date filtering of any kind.
- The calendar event's title was replaced by the AI title on every linked meeting before 2.10.0 (fixed for new meetings in 2.10.0), and it is not stored separately, so "the call with X on the 14th" was unfindable by its event title.

## Design

One shared engine, used by both platforms, with the query typed into the existing search field. Filters are typed tokens, and the same filters are available from a small filter row (people and date) so nobody has to learn the syntax.

### Query grammar (`MeetingSearchQuery.parse`)

- Plain words: every word must match somewhere in the meeting (AND). `"quoted phrase"` matches the phrase.
- `with:sam` or `with:sam@acme.com` or `with:acme.com`: attendee display name, email, domain, or a speaker name on the transcript. Repeatable; repeats are AND.
- `title:budget`: calendar event title (new `calendarEventTitle` field) or the meeting title.
- `on:2026-09-14`, `on:today`, `on:yesterday`, `on:14 sep`, `on:september`; `after:` and `before:` with the same forms; `last:7d`, `last:2w`, `last:3m`. Dates use the meeting's start time in the local time zone.
- `in:transcript`, `in:notes`, `in:summary`: restrict the plain words to one field. Optional, cheap to add.
- Unknown `key:value` tokens are treated as plain words, so an email with a colon never breaks the query.

### Matching and ranking

- Each plain word is matched independently across title, event title, attendees, speaker names, topics, notes, summary, action items, discussion flow, MEDDPICC, template sections, and transcript. A meeting qualifies only when every word and every filter matches.
- Score stays field-weighted as today (title highest, transcript lowest) summed per word; attendee and event-title matches score like the title. When a date filter is active, results are ordered by date, newest first, instead of by score, because the person is browsing a period.
- Snippet: the first matched field, with the matched term highlighted as today; an attendee or date match shows "with Sam Jones · 14 Sep" as the context line so the row explains why it matched.
- Performance: transcript text is joined once per meeting per revision and cached in a small dictionary keyed by `(id, transcriptRevision)`; the sidebar keeps its 250 ms debounce. 200 meetings with hour-long transcripts stay under a frame on an M-series Mac today; the cache removes the repeated joins.

### Data

- New `Meeting.calendarEventTitle: String?`, set when a meeting starts from or is linked to an event (same places `calendarEventId` is set). Lightweight SwiftData migration (optional field, default nil). Not backfilled; old meetings still match on attendees and date.
- Nothing new is sent anywhere. Search is local.

### UI

- macOS sidebar: the search field keeps its `/` shortcut. Below it, when the field is focused or a filter is active, a one-line filter row: **people** menu (attendees and speaker names across all meetings, sorted by how many meetings they appear in, searchable), **date** menu (today, yesterday, last 7 days, last 30 days, this month, last month, custom range with two date pickers), and a clear button. Choosing an item inserts the matching token into the field, so the typed form and the menus are the same thing and the field remains the single source of truth. Active tokens render as the plain text they are; no chip UI, no new control measurements.
- iOS History: same field, plus a `filter` button that opens a sheet with the people list and date presets; selections insert tokens the same way.
- Result rows: unchanged layout; the context line gains the "with … · date" form when a people or date filter matched.
- Empty state: "no meetings match. try fewer words, or `with:` a name and `on:` a date".
- Settings search registry: an entry so "search by person" and "search by date" find the History search help.

### Out of scope

- Semantic search and embeddings (explicitly not wanted; the reporter builds a local wiki with MCP instead).
- Saved searches, Spotlight indexing, cross-device search.
- Backfilling event titles for meetings recorded before 2.11.0.

## Tests

- `MeetingSearchQueryTests`: parser for every token form, quoted phrases, unknown keys falling back to words, date forms with an injected "now" and time zone, `last:` arithmetic.
- `MeetingSearchTests`: AND semantics across fields, attendee name/email/domain and speaker-name matching, event-title matching, date filters inclusive at day boundaries, ordering by date when a date filter is active, snippet context line, cache invalidation on `transcriptRevision` change.
- Both bundles (macOS and iOS) run the same sources.

## Rollout

Ships in 2.11.0 on macOS and iOS. Linux parity issue to be filed on build. Docs: `features/meeting-history.mdx` gets a "search" section with the grammar; changelog bullet: "search meetings by person, title, and date. Type with:sam, title:budget, on:14 sep, after:1 sep or last:2w, or pick them from the new people and date menus. Every word you type must now match, so sasha pricing finds the call about pricing with Sasha."

## Status

| Item | Status |
|---|---|
| Plan written | 2026-10-02 |
| `MeetingSearchQuery` parser + tests | done 2026-10-05 |
| Engine: AND, attendees, speakers, event title, dates, cache | done 2026-10-05 |
| `calendarEventTitle` on Meeting, set at start | done 2026-10-05 |
| macOS filter row + token insertion | done 2026-10-05 |
| iOS filter sheet + token insertion | done 2026-10-05 |
| Docs, changelog, Linux parity issue | done 2026-10-05 (Settings-search entry skipped: the registry only targets settings pages) |
| Manual check: find a weeks-old 1:1 by name, by date, by a transcript word | not started |
