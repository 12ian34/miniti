# Claude review brief

Fill in the actual values when dispatching. This is a review of an implementation slice, not a standing request to change code or review the whole repository.

```text
Goal: [user-visible outcome and owning package]
Repository and skill: [absolute repository path], [absolute miniti-pstack/SKILL.md path]
Source: [exact base and head SHA in each repo, or explicit named uncommitted snapshot]
Allowed scope: [files, entry points and affected boundaries]
Invariants: [billing/data/authorization/progress behavior that must hold]
Evidence: [commands, outputs and artifact paths at that source]
Previous findings: [IDs, dispositions, corrected commits and specific objections]
Excluded work: [unrelated or deferred changes]

Review independently using miniti-pstack's local adaptations. Do not edit shared files,
create commits, push, deploy, contact users or delegate further. Prefer safe reproducible
failures through real entry points. Return each finding with trigger, harm, source,
command/output when run, confidence, severity, new/inherited provenance and
Blocker/Follow-up/Question. Keep credible unexecuted concerns explicitly unverified.
Check whether claimed test results and artifacts support the actual acceptance criteria.
Distinguish a passing helper test from exercising the production call path.
For a recheck, inspect the named correction and affected boundaries; do not reopen the
entire candidate without new evidence or a stated coverage gap.
Report scoped closure and any evidence limitation. No verified findings is valid.
```

If changing files is necessary to reproduce a finding, the parent should provide a T3-managed isolated worktree at the reviewed head. A read-only reviewer can instead return the exact proposed repro and mark it unexecuted. Reproduction permission never includes live production mutation or customer data use.
