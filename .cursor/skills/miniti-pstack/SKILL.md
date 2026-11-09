---
name: miniti-pstack
description: "Use pstack practices for miniti implementation, exact-commit Claude review, and measured performance experiments. Use when Ian requests pstack or the agreed implementation/review loop. Keeps the release plan, source evidence and authorization boundaries authoritative."
---

# Miniti pstack

This is miniti's project adapter for selected Lauren Tan pstack practices, pinned and attributed in [UPSTREAM.md](UPSTREAM.md). It is not the complete upstream plugin. The source snapshots are reference material; their Cursor dispatch, model defaults, automatic PR creation and other skill dependencies are not installed commands. Use the workflow here and the active harness tools.

## Start from the requested mode

Read the root [AGENTS.md](../../../AGENTS.md), the relevant owning plan, and the [3.9.0 execution protocol and checkpoint](../../../docs/releases/3.9.0.md#implementation-hill-climb-with-claude). Keep that checkpoint current rather than creating a competing plan. Later releases use their own checklist.

- **Plan or investigate:** inspect, explain or update planning only. Loading this skill does not start implementation. Keep unresolved product choices explicit.
- **Implement:** after Ian starts the work, take the next dependency-ready slice through focused tests, local commit, Claude review and scoped correction/recheck. Preserve the selected scope and the unconfirmed split decision.
- **Review:** review the named base/head and boundaries. Return findings and evidence; do not modify the shared implementation checkout.
- **Measure:** use a bounded performance experiment only when the task has a real metric and target. Release completion is a set of acceptance gates, not a numeric optimization score.

Do not request permission again for actions already authorized in the session. Local implementation commit permission is recorded in the release protocol. It does not grant push, merge, deploy, migration, external distribution, submission or version-bump permission. No upstream playbook broadens that scope.

## Apply the selected practices

Load only the source relevant to the current step, and apply the adaptations below.

| Step | Pinned source | Miniti adaptation |
|---|---|---|
| Stateful account/usage/connection work | [Model the Domain](references/upstream/principle-model-the-domain.txt) | Name states, data ownership, authorized transitions and late/retried results before adding logic. Use a small typed model or transition table where it removes invalid states; no unsolicited whole-app state-machine rewrite. |
| Each implementation slice | [Sequence verifiable units](references/upstream/principle-sequence-verifiable-units.txt) | Code, regression tests and related docs form one coherent tested local commit. Demonstrate a critical regression test can fail before the fix, but commit a green slice. Keep review fixes in separate commits; do not silently amend a reviewed SHA or rebase unrelated work. |
| Claude package review | [Interrogate](references/upstream/interrogate.txt) | Prefer executable repros with command, actual/expected result and exact source. Astra reruns practical safe repros. Preserve credible unexecuted security, data or migration concerns as **unverified**, with evidence/confidence and a verification gate, instead of dropping them. No reviewer quorum or large swarm. |
| Closure and resume | [Show me your work](references/upstream/show-me-your-work.txt) | Use the existing audit's implementation queue and release checkpoint. Record decision, reason, source/evidence, outcome and closure; link detailed logs. Claude checks evidence supports the claim as part of the same review, not a second audit process. Keep private transcript links and customer data out of tracked files. |
| Two failed fixes sharing an assumption | [Attack the Premise](references/upstream/principle-attack-the-premise.txt) | Write the shared assumption and a discriminating probe before a third patch. Preserve failed evidence and explain any changed design. |
| Performance claim | [Hillclimb](references/upstream/hillclimb.txt), [Benchmark checklist](references/upstream/benchmark-checklist.txt) | Reproduce a realistic workload, validate then freeze the harness, count errors and completed work, alternate repeated before/after runs, and retain only measured wins with green regression gates. Correctness outranks speed. Adapt system tools to macOS; do not assume Linux commands exist. |

## Delegate reviews through T3

Use the session's T3 orchestration instructions. Discover current tool/provider support when required; a pinned skill does not establish model availability. Use a fresh `delegate_task` targeting Claude for each review/recheck. Keep Astra as implementer/coordinator and Claude as independent reviewer unless Ian changes roles. Do not inherit upstream Grok defaults, launch extra top-level chats, create shell worktrees for delegates or install another runner.

Read-only shared review is appropriate for an exact committed slice whose reviewed files remain frozen. If a repro needs files changed, use a T3-managed isolated worktree based on the reviewed commit. Uncommitted files are not copied automatically. Pass the brief in [references/review-brief.md](references/review-brief.md), including this skill's absolute path. Review children do not delegate again. Follow completion notifications and any returned `next` instruction; no status polling or timers around a running delegate. If Claude is unavailable, report that limitation and keep independent-review acceptance open; do not silently substitute another reviewer.

Use the active device-panel tools for native UI work. No Cursor-only control skill, browser skill, simulator driver or PR tool is implied by this adapter. For the actual implementation, also read the relevant project color, target-membership and changelog skills.

## Close the slice

Use the release protocol's blocker threshold and stopping rules. Link the exact tested/reviewed commit set across affected repos, record fixed/deferred/disputed/unverified findings, and advance only when required acceptance evidence exists. Missing hardware/provider evidence stays a gate. Do not restart a whole-tree review after a small correction without a named coverage gap.

At handoff, report the completed slice, evidence, remaining gate and next action. The existing checkpoint owns resumability. Installing this skill creates no scheduled service, release authorization or promise that an idle thread runs indefinitely.

## Validate the installation

From the repository root, run `python3 .cursor/skills/miniti-pstack/scripts/check_install.py` to check the pin, byte hashes and discovery links. Run the release-planning link/public-reference checks when this adapter or its repo references change. See [UPSTREAM.md](UPSTREAM.md) for the update procedure and differences from upstream.
