# UI source guard and existing debt

The UI3 guard runs on Python's standard library, without Xcode or sibling repositories. It is a bounded source check, not a Swift compiler or an accessibility audit. Its baseline records existing debt; it does not approve the appearance or behaviour of those call sites.

```sh
python3 -m unittest discover -s scripts/tests -p 'test_ui_source.py' -v
python3 scripts/check-ui-source.py
python3 scripts/check-ui-source.py --inventory
```

The first two commands run in the `runner-contract` job in [tests.yml](../../.github/workflows/tests.yml). `--inventory` prints every matching occurrence with its current path and line. The machine-readable [baseline](../../scripts/ui-source-baseline.json) records normalized call signatures and counts per file. The [checker](../../scripts/check-ui-source.py) never regenerates or expands that baseline automatically.

## Scope and decisions

All Swift sources under `Miniti/` and `MinitiMobile/` are scanned, including app roots, helpers and panels. This avoids losing coverage when view helpers move out of a Views directory. Only `Miniti/Models/ColorPalette.swift` is excluded, because it defines the canonical raw colours. It also contains typography definitions; those remain reviewed code rather than guard findings. Tests, Watch and Live Activity sources are outside the main-app scope; D18 owns extension token adoption. Asset files and export strings are data, not scanned Swift colour constructors. No whole export source file is exempted. New exclusions require a specific reviewed reason and a fixture.

| Rule | Check | Outcome for a new occurrence |
|---|---|---|
| `raw-color` | Explicit `Color`, `NSColor`, `UIColor` or `CGColor` constructors with hex/component labels, including qualified and explicit type `.init` forms; `#colorLiteral` | Fails. Add or reuse a semantic palette role. Variables supplied to raw component parameters also count, so splitting a literal into a local variable does not avoid the rule. |
| `focus-opt-out` | `focusable(false, …)` | Prints `REVIEW`. Check native keyboard/focus ownership; there are legitimate exceptions. |
| `small-fixed-font` | Direct numeric `system(size:)` and native system-font arguments below 13pt | Prints `REVIEW`. Decide whether this is prose, a compact label or an icon and check the platform/scale contract. No arbitrary font-size ban. |
| `local-chrome` | Numeric `cornerRadius` modifiers or rounded-rectangle constructors | Prints `REVIEW`. These are candidates for duplicated styling, not proof of a control or of duplication. Prefer shared roles where appropriate; native/custom drawing may be legitimate. |

Review cues do not fail CI. They remain visible on subsequent runs until corrected or explicitly added to the baseline after a scoped review records the reason in the owning change. Do not refresh the whole baseline to silence new output. Raw-colour additions are failures; accepting new colour debt would be an explicit exception to the palette policy, not routine baseline maintenance.

Whitespace and comments do not affect signatures. Nested block comments and ordinary/raw/multiline string prose are ignored; executable string interpolations are scanned, including nested strings. Both conditional-compilation branches are scanned. Named assets and bridges from palette/native colours are allowed. This does not resolve aliases, inferred `.init`, macros, function references, computed expressions or shorthand colour members. Swift regex literals are not parsed as regex syntax and can produce a diagnostic or false positive. Review unfamiliar syntax before changing the checker or its scope. It cannot prove a semantic role is appropriate, measure rendered contrast/targets, identify every small font expression or establish VoiceOver/focus behaviour.

Counts are local to a file and exact signature, rather than line numbers. Adding another identical call, changing its raw value or moving it to another file needs reconciliation. Moving an unchanged call within the same file, or replacing a removed call with an identical one in that same change, is not distinguished. Review those moves in the diff. Previously removed debt cannot return after its allowance is pruned.

## Removing debt

Removing or changing a recorded call makes its old allowance stale, which fails the check. After a deliberate removal, run:

```sh
python3 scripts/check-ui-source.py --prune-baseline
python3 scripts/check-ui-source.py
```

Pruning only removes entries or decreases counts. It refuses to write when new raw colours are present, never adds new review cues and never increases an allowance. Include the resulting baseline diff with the source change. File deletion is treated the same way. A missing source root, malformed source delimiters/strings, invalid baseline or unreadable file is an error, not an empty clean scan.

## Captured debt, 2026-11-10

Initial inventory against Apple source `e177b5bd`: 80 scanned Swift files, 333 raw-colour occurrences, 54 focus opt-outs, 608 small fixed-font cues and 188 local-chrome cues. The 1,183 occurrences occupy 326 file/rule/signature entries. These totals include repeated calls, icons and legitimate compact geometry. They are not defect counts. The source is unchanged in this enforcement slice.

| File | Raw colours | Disposition |
|---|---:|---|
| `Miniti/Views/MeetingView.swift` | 107 | Live insight, API/status, investigation and utility surfaces. UI3 inventories remaining meaningful text; wider chrome/status work follows D10/D13/D16 in the owning plan. |
| `Miniti/Views/InsightsView.swift` | 100 | Docs, empty/generating states, per-speaker Coaching, table/card drawing. Meaningful text requires role review; remaining renderer/help extraction follows D11/D12. |
| `Miniti/Views/TranscriptView.swift` | 44 | Speaker/transcript chrome and loading/empty states. Preserve speaker identity and incremental text behaviour; use UI3 contrast evidence for touched text. |
| `Miniti/Views/UsageBanner.swift` | 34 | Account/usage status, owned by account ownership's D16 follow-through. No current entitlement or copy change. |
| `Miniti/Views/MainWindow.swift` | 25 | History and remaining navigation/utility chrome, D11/D15/history owner. Shared standard section/list corrections do not close every legacy role. |
| `MinitiMobile/Views/MeetingView_iOS.swift` | 13 | Usage/placeholder and catch-up/insight text. Account and live-UI owners retain their boundaries. |
| `MinitiMobile/Views/HistoryView_iOS.swift` | 5 | Saved title/cloud/insight surfaces, history and meeting-ownership follow-through. |
| `Miniti/Views/LimitWarningBanner.swift` | 4 | Account/limit presentation, D16/account ownership. |
| `Miniti/Views/SettingsView.swift` | 1 | Pro plan/billing label (`A78BFA`), D17/account ownership when that surface changes. |

The [UI plan's ownership register](../plans/ui-consistency-and-accessibility.md#audit-ownership-register) remains authoritative; this inventory assigns no new release scope. In particular:

- Review C1-F1: [per-speaker filler count](../../Miniti/Views/InsightsView.swift) at the captured line 1649 (`FillerWordsSection`) still uses `71717A` for “N fillers (x/min)”. It is meaningful text and remains an open UI3 contrast item. `MeetingView` also retains `71717A` at captured line 1522 (API label), 1977 (sidebar action icon) and 2370 (live Mac filler count), plus disabled/status uses. Inspect each role and actual background/opacity rather than substituting every occurrence with one token.
- Review C1-F2: `TrainingStatsOverview` still constructs its panel `0F0F11` and border `1C1C1F` at captured lines 3296/3299. They match the current palette roles; this is inherited token debt, not a new contrast defect.
- `InsightsView` still has `484F58`/`52525B` on docs, loading/empty and helper content (captured lines 567, 712–720, 842–897, 1074–1128, 1198, 1623 and 3821–3860). The baseline is not an ordinary-text contrast exemption. Resolve meaningful prose/actions under UI3, and distinguish genuinely decorative or disabled content.
- Success/tertiary Copy hover evidence is a role-pair contrast calculation. It is not a hovered render; physical pointer and disabled-hover acceptance remain open.

Use `--inventory` for current locations as source lines move. UI1/UI2/UI3 whole-screen, iPad, largest-text, keyboard, VoiceOver, pointer, appearance, performance and final candidate suites remain separate gates in the [release record](../releases/3.9.0.md).
