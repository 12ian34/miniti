# Granola import plan: reading the export Granola makes today

> Historical implementation/review record, archived 2026-10-27. It includes superseded proposals and dated statuses, not current instructions. Use [the roadmap](../roadmap.md) for priorities and [the disposition register](README.md) for the current owner of remaining work and contracts. Old “not built”, “uncommitted” and release gates below describe their original snapshot.

> Started 2026-10-23 after a user said the Granola import "doesn't work very well". Ian generated a fresh export the same day (`granola-export-2026-10-23.zip`, 33 meetings, one CSV part, 1 MB) and the importer refused every row. This doc records what the export looks like now, what was wrong, what changed in `GranolaCSVImporter.swift`, and what the Linux client still has to mirror. The sample export stays on Ian's machine; nothing from it is in the repo.

## Status

| Step | Status | Notes |
|---|---|---|
| Recognise the current columns | **Built 2026-10-23** | `document_id, user_email, document_title, workspace_name, document_created, summary, notes, transcript`. `documenttitle` and `documentcreated` matched nothing, so the title fell back to "untitled" and every row was skipped for "missing a date". Aliases added, plus a general rule: a header not known as written is retried with a `document`, `note`, `meeting` or `granola` prefix removed. `user_email` is the owner |
| Transcripts without speakers | **Built 2026-10-23** | 30 of the 33 transcripts are one short fragment per line ("Yeah.", "the average talk time indicator and the"), no speaker, no time. The old parser merged all of them into one segment. Now lines are joined until a sentence ends (or 60 words), each chunk is one turn, every turn is the same unnamed speaker (S1), nobody is You. A transcript where at least half the lines carry `Name:` keeps the old labelled behaviour (3 of the 33: `Speaker A:` to `Speaker F:`, generic so no names) |
| Meeting length | **Built 2026-10-23** | The export has no end time and no timings, so the old import had a 0:00 meeting and every turn at the same second. Length is now estimated at 150 words a minute from the transcript (2,847 words: 19 min). Turn timestamps sit where their words fall. A row with an end column, JSON timings or `[mm:ss]` prefixes still uses those |
| Summary markup | **Built 2026-10-23** | The `summary` column is markdown: a `#` title line repeating the meeting title, `###` sections, bullets, and backslash escapes (`\&` in 22 of 33 rows). miniti shows a summary as plain text, so the title line goes, heading hashes and `**` go, escapes are undone, bullets stay |
| The zip itself | **Built 2026-10-23** | Granola emails a zip holding `granola-export-<date>/granola-export-<date>-000.csv` (more parts for big accounts). The file picker takes the zip, or several CSV files at once; a 120-line reader opens stored and deflated entries, skips folders and `__MACOSX`, refuses zip64 or encrypted archives with "unzip it and import the CSV files inside" |
| Tests | **Built 2026-10-23** | `MinitiTests/MeetingModelTests.swift`, Granola section: the export's columns end to end (sentences, estimate, word-placed timestamps, summary cleanup), labelled lines with continuations, plain-text summary cases, a zip with two parts (one stored, one deflated) plus noise entries, a zip without a CSV. A one-off run against the real export parsed all 33 rows (see "Checked against the real export") |
| Linux | header fix committed 2026-10-23, rest owed | `../miniti-linux/src-tauri/src/import/granola.rs` had the same alias lists; `canonical_header` and the three aliases are in with a test. Sentence joining, the length estimate, summary cleanup and the zip are listed in `../miniti-linux/PLAN.md` "To mirror (2026-10-23)" |
| Release | owed | Changelog entry under Unreleased v3.4.0. Ships with the next Mac and iOS release |

## What the export looks like

One CSV per 1 MB or so, UTF-8, RFC 4180 quoting, header row:

| Column | What it holds | Used as |
|---|---|---|
| `document_id` | Granola's note UUID | `externalID` (duplicate protection, cloud uniqueness) |
| `user_email` | the Granola account | owner (marks self if an attendee column ever appears) |
| `document_title` | the note title | title |
| `workspace_name` | Granola workspace | ignored |
| `document_created` | ISO 8601 with milliseconds | start time |
| `summary` | Granola's AI notes, markdown | summary, flattened to plain text |
| `notes` | what the person typed | notes, verbatim |
| `transcript` | one fragment per line, or `Speaker A: …` lines | segments |

Nothing else: no end time, no attendees, no calendar event, no URL, no timings, no speaker identity for the usual case.

## Why one speaker and an estimate

Granola's own app knows which side of the call each line came from, but the bulk export drops it. Guessing turns by alternation would be wrong often and look right, which is worse than an honest S1 for everyone. The length estimate is the only way to give History a duration and the transcript a timeline; 150 words a minute is ordinary conversation, and the number lives in `GranolaCSVImporter.estimatedWordsPerMinute`. Settings says so next to the import button.

## Checked against the real export

2026-10-23, the parsing half of `GranolaCSVImporter.swift` compiled on its own with `swiftc -enable-bare-slash-regex` and run on the zip Ian generated (not committed): 33 meetings in 0.23 s, 0 rows skipped, every title and date read, the 3 labelled transcripts kept their 4 to 6 speakers, the 30 unlabelled ones came out as 51 to 772 sentence turns, estimated lengths 3 to 64 minutes, every summary opened on its first section rather than a `#` title. A line Granola wrote as one long paragraph stays one turn (up to 272 words), the 60-word cap only stops joining. Doing the same inside the sandboxed macOS test host hangs: a test that reads a file under `~/Downloads` puts up a files permission dialog the host cannot dismiss, and one copied into the host's container did not get past a shield window either, so the standalone build is the way to check a real export.

## Manual checks owed

- [ ] macOS: Settings, Data, Import… pick the zip; History shows the 33 meetings with lengths, the transcript shows sentence turns, the summary has no `###` or `\&`. Import again: "33 already imported".
- [ ] iOS: same from the Files app with the zip still zipped.
- [ ] One meeting on both devices with cloud on: one copy in the cloud.
