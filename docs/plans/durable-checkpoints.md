# Reduce finalized transcript loss after an abrupt exit

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Original P0.4: measure and shorten the durable checkpoint interval for finalized transcript changes, targeting a coalesced 5–10 second experiment. Unfinalized interim speech remains best effort. No new backup/cloud product or save-queue rewrite.

## Implementation and tests

Measure save cost first. Keep per-meeting coalescing, off-main planning, revision fences, background leases and termination fail-open behavior. Never replace this with one global latest payload. T11 disk-backed journey tests and relevant T09 start/stop/handoff tests belong here. Reproduce forced termination, rapid handoff, resume, deletion during save, failed write and long transcripts with reload from disk, not an in-memory “relaunch”.

## Acceptance and rollback

Document the measured maximum finalized-content loss, write frequency, main-thread stalls and recovery behavior on both platforms. It must be materially below the present 60-second checkpoint boundary without resurrection or cross-meeting payload loss. Return to the old cadence if resource budgets regress; preserve the queue and persisted data. Hardware/OS termination evidence stays in the release record.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
