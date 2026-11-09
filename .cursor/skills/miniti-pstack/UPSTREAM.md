# Upstream provenance and local adaptations

Source: [Lauren Tan's pstack in cursor/plugins](https://github.com/cursor/plugins/tree/236e5481d05cbadc315b374a5de54971858c27bb/pstack), commit `236e5481d05cbadc315b374a5de54971858c27bb`. The [MIT license](LICENSE) preserves the upstream copyright notice. This is a local project adaptation, not an upstream-endorsed distribution or the complete pstack plugin.

[upstream-lock.json](upstream-lock.json) records the original path and SHA-256 of each included source file. The six source skill documents, hillclimb playbook and license are byte-for-byte copies at that revision. Source skill/playbook documents use `.txt` extensions so they remain reference material rather than independently discoverable skills with missing dependencies. Relative links and commands inside those snapshots refer to the upstream repository; they are not local installation instructions. Follow the adapter's mapped links and procedures instead.

The skill-installer helper retrieved the six skills from the pinned public repository into temporary staging. Only their reviewed document files were retained. No upstream scripts, hooks, agents, model configuration, auto-updater or global plugin settings were installed. `SKILL.md`, the review brief, metadata and installation validator are local miniti files.

## Deliberate differences

- One coordinator and Claude review through T3, using the active tool/provider contract. No upstream Cursor/Grok model dispatch, automatic subagent fan-out, PR opening, merging or scheduled wake commands.
- Commit code/tests/docs as a coherent green slice. Regression tests should demonstrate failure before the fix, but we do not require standalone failing commits or an automatic rebase onto trunk.
- Practical executable evidence is preferred. Credible risks that cannot yet be reproduced remain labelled unverified; missing evidence is not clearance.
- The existing release checklist and implementation queue own status and decisions. No duplicate TSV status system or automatic scan of private conversations.
- Performance experiments use workload/error counts and repeatable measurements. The full release uses acceptance gates, with existing scope, publication and migration rules intact.

## Updating the pin

Updates are explicit maintenance work, not automatic. Fetch a chosen full commit from `cursor/plugins` into temporary staging with the skill-installer helper, inspect the diff for the paths in `upstream-lock.json`, and review any changed license or dependencies. Copy only the selected source documents, preserving bytes; update the commit and hashes together. Reconcile relevant local adaptations rather than executing new upstream directives. Run the validator, its tests, skill frontmatter validation, repo link/public-reference checks and `git diff --check`. Keep the current pin if the new upstream behavior conflicts with the intended workflow.

## Discovery and use

The canonical skill is `.cursor/skills/miniti-pstack`. Relative symlinks at `.agents/skills/miniti-pstack` and `.claude/skills/miniti-pstack` expose the same source to Codex and Claude. Existing global skill directories are untouched. Use `$miniti-pstack` in Codex, or `/miniti-pstack` where the harness exposes project skill commands. Otherwise explicitly ask the agent to read `.cursor/skills/miniti-pstack/SKILL.md`. Discovery refresh is harness-owned; the files and explicit path are available immediately, and a new turn/session can refresh the skill catalog.
