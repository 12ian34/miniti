# Reduce finalized transcript loss after an abrupt exit

Status: scoped future work, not implemented; version unassigned. Reconciled 2026-10-27. Priority is in [the roadmap](../roadmap.md). This is a bounded deliverable, not an ongoing maintenance programme. Confirm design and release scope before implementation.

## Scope

Original P0.4: measure and shorten the durable checkpoint interval for finalized transcript changes, targeting a coalesced 5–10 second experiment. Unfinalized interim speech remains best effort. No new backup/cloud product or save-queue rewrite.

## Implementation and tests

Measure save cost first. Keep per-meeting coalescing, off-main planning, revision fences, background leases and termination fail-open behavior. Never replace this with one global latest payload. T11 disk-backed journey tests and relevant T09 start/stop/handoff tests belong here. Reproduce forced termination, rapid handoff, resume, deletion during save, failed write and long transcripts with reload from disk, not an in-memory “relaunch”.

## State-machine acceptance criteria

Mapped on 2026-11-09 from the [Apple-app inventory](../research/implicit-state-machines-2026-11-08.md): R1–R4 (session, finalization, handoff and save queue), D1/D2 (commit failure and deletion), D3/D4 (delivery checkpoints) and P1 (termination/background leases). Use these boundaries to validate the checkpoint experiment within the existing save queue.

- Distinguish capture stopped, transcript durable, AI settled and delivery released. Hold final AI while starting another meeting; assert that the first transcript is durable and neither meeting's save payload or completion identity is replaced by the other.
- Interrupt rapid handoff/resume and coalesced writes, then reopen the actual disk store. Assert per-meeting revisions and finalized content against the measured checkpoint bound. A stale save after deletion must not resurrect the meeting.
- Inject a failed write before a checkpoint or delivery handoff. Assert the durable watermark does not advance, an in-process retry saves the latest valid revision, and reopening recovers the last successful checkpoint. No completion marker may advance ahead of the required durable save.
- Exercise termination/background completion against a held save and its deadline. Assert the lease/completion is released once and the resulting disk contents match the acknowledged checkpoint; keep physical OS termination evidence separate.

Extend existing meeting-journey, handoff and outbox coverage with disk-backed assertions. Preserve the valid overlap of a new recording with an older meeting's AI finalization. This work does not require a replacement session enum, save-queue rewrite or state-machine framework.

## Acceptance and rollback

Document the measured maximum finalized-content loss, write frequency, main-thread stalls and recovery behavior on both platforms. It must be materially below the present 60-second checkpoint boundary without resurrection or cross-meeting payload loss. Return to the old cadence if resource budgets regress; preserve the queue and persisted data. Hardware/OS termination evidence stays in the release record.


## Release contract

Record before/after evidence and run the affected backend checks and both Apple bundles for shared client changes. Update current reference docs and the per-platform release record. Preserve existing data and compatible old clients. Shared backend changes require Linux tracking. No deployment is authorized by this document. Close the whole stated scope when shipped; unrelated discoveries become separate roadmap items.
