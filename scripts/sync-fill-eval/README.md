# Server-side fill evaluation (3.10.0 SM1.5)

Evidence for the decision in the [3.10.0 plan](../../docs/releases/3.10.0.md) (package SM1.5): should the backend return `external_source: null` and `external_id: null` in the sync documents it serves, so that 3.8.0 and 3.9.0 devices stop uploading meetings again?

The patch adds a scratch test to the unchanged v3.9.0 source. It runs the real 3.9.0 sync engine, two or three devices on one account, against a fake server that drops the two null keys when storing (as production does) and can serve them back as explicit nulls. It makes no network calls and uses no customer data.

## Run

```bash
git worktree add --detach /tmp/miniti-390 v3.9.0
cd /tmp/miniti-390
ln -s "$OLDPWD/Miniti/Resources/NemotronDiarizer" Miniti/Resources/NemotronDiarizer
git apply "$OLDPWD/scripts/sync-fill-eval/v3.9.0-evaluation.patch"
xcodebuild test -scheme Miniti -destination 'platform=macOS' -only-testing:MinitiTests/Sm15Evaluation \
  -derivedDataPath /tmp/miniti-390-dd 2>&1 | grep SM15RESULT | sort -u
cd - && git worktree remove --force /tmp/miniti-390
```

## Result, 2026-11-15 (v3.9.0 at `2c65b010`)

| Check | Today (keys absent on read) | With the fill |
|---|---|---|
| Uploads after one folder change, two devices | 2 (1 is the change) | 1 |
| Uploads after one folder change, three devices | 2, settled in 2 rounds | 1, settled in 1 round |
| A edits content, B (merged before) makes a later folder move before downloading | A's edit lost on both | A's edit kept on both, folder moved |
| A edits but cannot upload, B uploads a later folder-only change first | A's edit lost on both | A's edit kept on both, folder moved |

Turning the fill on for devices whose baselines were made without it, 10 meetings:

| Check | Result |
|---|---|
| Uploads caused by turning it on, nothing else changed | 0 |
| First folder change per meeting afterwards | 10 uploads, the 10 changes, settled in 1 round |
| Second folder change per meeting | 10 uploads, the 10 changes |
| Edit on A after the switch, later folder move on B, for a meeting B has merged since the switch | edit kept |
| The same for a meeting B has not merged since the switch | edit lost once, as today |
| That meeting, a second time | edit kept |

Changing the served form while a device has an edit it could not upload yet. B holds a baseline from a merge, edits notes, and is offline; A then uploads a later folder-only move; B retries and gets the conflict document:

| Served form | B's edit |
|---|---|
| Absent throughout (today) | kept |
| Filled throughout | kept |
| Turned on while B's edit is pending | lost on both devices |
| Turned off while B's edit is pending | lost on both devices |

## Conclusion: not safe to turn on (rejected, 2026-11-15)

Once every device's baselines are in the filled form, the fill stops the repeated uploads and both edit-loss sequences. Getting there is the problem. A 3.8.0 or 3.9.0 device keeps baselines in whatever form it last saw, so at the moment the served form changes, an edit that is waiting to upload on such a device can be discarded when another device's later folder change arrives. That edit survives today. Turning the flag off again does the same in the other direction, so there is no safe rollback either: the flag changes what the server sends, not the baselines devices already hold. This was found in review; the first version of this file wrongly said nothing gets worse.

The plan's test for SM1.5 was that no sequence gets worse. One does, so the fill is not turned on. 3.10.0 fixes the cause on the device, and the 3.10.0 engine is unaffected by either served form (`SyncMergeFormTests.testServedExplicitNullsChangeNothingForACurrentDevice`).

Limits: a fake server, not production. It models only the dropping of null external keys. Production also removes blank external strings, trims and cuts external values, cuts titles to 500 UTF-16 units, defaults an empty language and the transcript revision, and normalises dates and ids; a 3.8.0 or 3.9.0 device whose local value differs from the stored one (a title over the limit, for example) has a mismatched baseline that the fill does not repair, so the "with the fill" columns above hold only for meetings without such values. One account shape. Meetings with a missing baseline or waiting for a folder refresh were not run. 3.8.0 was not run separately: `CloudSyncEngine.swift` and `MeetingSyncDocument.swift` are identical in v3.8.0 and v3.9.0 (`git diff v3.8.0 v3.9.0` on the two files is empty), so the result covers both.
