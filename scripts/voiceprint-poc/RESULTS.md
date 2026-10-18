# Voice print POC results (2026-10-19, all six sessions)

Offline only. CAM++ speaker embeddings (FluidAudio 0.17.4, the package miniti ships; 192-d, L2-normalised, cosine similarity) over AMI ES2004a/b/c and IS1009a/b/c: the same four people per series on three different days, each session as the headset mix (a good call) and one far-field array mic in the room (the hard case: a phone on the table). Reference turns from the pyannote `only_words` RTTMs, overlap removed. Windows of 6 s of one person's own speech.

## Reading it

- **Speed**: 6 ms per window. Negligible.
- **Single windows are not enough**: 5.5% equal error rate within a session, 8.1% across days on the same mic, 11.5% across mics, 14.8% across both. The product never matches on one window.
- **The product's unit, a 30 s per-speaker average against a print learnt from 30 s**, is what the "averaged probes" tables measure:
  - Same kind of microphone, a different day, threshold 0.60: headset to headset 100% correct, no false accepts, every pair (ES2004a to b and c, IS1009a to b and c). Room mic to room mic: 76 to 100% correct; the ES2004 room mic across days is the weakest at 76% with 24% false accepts to b and 91%/9% to c, IS1009 96 to 100%.
  - Across microphones and days (enrolled on a headset, met again on a room mic or the reverse): 38 to 88% correct, but the misses are almost all **unassigned**, not wrong: false accepts stay at 0 to 4%. The matcher refuses rather than guesses, which is the behaviour the confirm band (0.45 to 0.60) is designed for; at 0.45 to 0.50 most of those become suggestions.
- **Within a session** (enrol from the first 60 s, match 30 s averages from the second half): 100% correct, no false accepts, both series, both mics, 0.4 to 0.6.

## Verdict against the plan's gates

- Headset, within and across days: pass, clearly.
- Across microphones: a pass on the IS1009 series, a near miss on ES2004 where the room mic across days produces some confident wrong matches at 0.60. The product mitigates this three ways: prints accumulate across meetings (the tables enrol from a single 30 s), "You" is matched first and one print can take only one speaker, and a wrong confident match can be undone from the rename sheet. Worth watching in Ian's real-world test with the phone on a table.
- Thresholds stay at 0.60 match and 0.45 confirm. A later improvement is per-microphone prints (keep a headset and a room-mic vector per person), which the cross-mic rows suggest would help.

## Speakers per session (windows of own speech, 6 s each)

- ES2004a Array1-01: FEE013 51, FEE016 31, MEE014 16, MEO015 12
- ES2004a Mix-Headset: FEE013 51, FEE016 31, MEE014 16, MEO015 12
- ES2004b Array1-01: FEE013 102, FEE016 83, MEE014 75, MEO015 42
- ES2004b Mix-Headset: FEE013 102, FEE016 83, MEE014 75, MEO015 42
- ES2004c Array1-01: FEE013 76, FEE016 59, MEE014 113, MEO015 52
- ES2004c Mix-Headset: FEE013 76, FEE016 59, MEE014 113, MEO015 52
- IS1009a Array1-01: FIE088 57, FIO084 5, FIO087 7, FIO089 18
- IS1009a Mix-Headset: FIE088 57, FIO084 5, FIO087 7, FIO089 18
- IS1009b Array1-01: FIE088 70, FIO084 68, FIO087 49, FIO089 80
- IS1009b Mix-Headset: FIE088 70, FIO084 68, FIO087 49, FIO089 80
- IS1009c Array1-01: FIE088 65, FIO084 89, FIO087 51, FIO089 32
- IS1009c Mix-Headset: FIE088 65, FIO084 89, FIO087 51, FIO089 32

## Windows and speed

| session | mic | windows | speakers | ms per window |
|---|---|---|---|---|
| ES2004a | Array1-01 | 110 | 4 | 6 |
| ES2004a | Mix-Headset | 110 | 4 | 6 |
| ES2004b | Array1-01 | 302 | 4 | 7 |
| ES2004b | Mix-Headset | 302 | 4 | 6 |
| ES2004c | Array1-01 | 300 | 4 | 7 |
| ES2004c | Mix-Headset | 300 | 4 | 6 |
| IS1009a | Array1-01 | 87 | 4 | 6 |
| IS1009a | Mix-Headset | 87 | 4 | 6 |
| IS1009b | Array1-01 | 267 | 4 | 6 |
| IS1009b | Mix-Headset | 267 | 4 | 6 |
| IS1009c | Array1-01 | 237 | 4 | 7 |
| IS1009c | Mix-Headset | 237 | 4 | 6 |

## Same versus different speaker, cosine similarity

| condition | pairs | same: mean (p5) | different: mean (p95) | EER | threshold at EER |
|---|---|---|---|---|---|
| within session | 654056 | 0.764 (0.590) | 0.416 (0.606) | 5.5% | 0.613 |
| across sessions, same mic | 527894 | 0.719 (0.536) | 0.418 (0.604) | 8.1% | 0.592 |
| across mics, same session | 328331 | 0.549 (0.396) | 0.294 (0.490) | 11.5% | 0.431 |
| across sessions and mics | 527894 | 0.524 (0.366) | 0.297 (0.494) | 14.8% | 0.409 |

## Identification within a session: enrol from the first 20 s, identify the second half

| session | mic | threshold | correct | false accept |
|---|---|---|---|---|
| ES2004a | Array1-01 | 0.409 | 76.8% | 23.2% |
| ES2004a | Array1-01 | 0.431 | 76.8% | 23.2% |
| ES2004a | Array1-01 | 0.500 | 75.0% | 23.2% |
| ES2004a | Array1-01 | 0.592 | 62.5% | 23.2% |
| ES2004a | Array1-01 | 0.600 | 60.7% | 23.2% |
| ES2004a | Array1-01 | 0.613 | 58.9% | 21.4% |
| ES2004a | Array1-01 | 0.700 | 30.4% | 0.0% |
| ES2004a | Mix-Headset | 0.409 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.431 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.500 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.592 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.600 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.613 | 96.4% | 0.0% |
| ES2004a | Mix-Headset | 0.700 | 91.1% | 0.0% |
| ES2004b | Array1-01 | 0.409 | 94.1% | 5.9% |
| ES2004b | Array1-01 | 0.431 | 94.1% | 5.9% |
| ES2004b | Array1-01 | 0.500 | 93.4% | 5.3% |
| ES2004b | Array1-01 | 0.592 | 86.2% | 2.6% |
| ES2004b | Array1-01 | 0.600 | 83.6% | 2.6% |
| ES2004b | Array1-01 | 0.613 | 81.6% | 1.3% |
| ES2004b | Array1-01 | 0.700 | 49.3% | 0.0% |
| ES2004b | Mix-Headset | 0.409 | 75.7% | 24.3% |
| ES2004b | Mix-Headset | 0.431 | 75.7% | 24.3% |
| ES2004b | Mix-Headset | 0.500 | 75.7% | 24.3% |
| ES2004b | Mix-Headset | 0.592 | 72.4% | 16.4% |
| ES2004b | Mix-Headset | 0.600 | 72.4% | 15.1% |
| ES2004b | Mix-Headset | 0.613 | 71.7% | 13.2% |
| ES2004b | Mix-Headset | 0.700 | 67.1% | 0.0% |
| ES2004c | Array1-01 | 0.409 | 95.4% | 4.6% |
| ES2004c | Array1-01 | 0.431 | 95.4% | 4.6% |
| ES2004c | Array1-01 | 0.500 | 95.4% | 4.6% |
| ES2004c | Array1-01 | 0.592 | 94.7% | 4.6% |
| ES2004c | Array1-01 | 0.600 | 94.7% | 4.6% |
| ES2004c | Array1-01 | 0.613 | 91.4% | 4.0% |
| ES2004c | Array1-01 | 0.700 | 73.5% | 0.0% |
| ES2004c | Mix-Headset | 0.409 | 100.0% | 0.0% |
| ES2004c | Mix-Headset | 0.431 | 100.0% | 0.0% |
| ES2004c | Mix-Headset | 0.500 | 100.0% | 0.0% |
| ES2004c | Mix-Headset | 0.592 | 99.3% | 0.0% |
| ES2004c | Mix-Headset | 0.600 | 99.3% | 0.0% |
| ES2004c | Mix-Headset | 0.613 | 99.3% | 0.0% |
| ES2004c | Mix-Headset | 0.700 | 96.7% | 0.0% |
| IS1009a | Array1-01 | 0.409 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.431 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.500 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.592 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.600 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.613 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.700 | 78.6% | 0.0% |
| IS1009a | Mix-Headset | 0.409 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.431 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.500 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.592 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.600 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.613 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.700 | 97.6% | 0.0% |
| IS1009b | Array1-01 | 0.409 | 79.9% | 20.1% |
| IS1009b | Array1-01 | 0.431 | 79.9% | 20.1% |
| IS1009b | Array1-01 | 0.500 | 79.9% | 20.1% |
| IS1009b | Array1-01 | 0.592 | 74.6% | 17.9% |
| IS1009b | Array1-01 | 0.600 | 73.1% | 17.9% |
| IS1009b | Array1-01 | 0.613 | 68.7% | 17.2% |
| IS1009b | Array1-01 | 0.700 | 47.0% | 9.7% |
| IS1009b | Mix-Headset | 0.409 | 100.0% | 0.0% |
| IS1009b | Mix-Headset | 0.431 | 100.0% | 0.0% |
| IS1009b | Mix-Headset | 0.500 | 100.0% | 0.0% |
| IS1009b | Mix-Headset | 0.592 | 94.8% | 0.0% |
| IS1009b | Mix-Headset | 0.600 | 94.0% | 0.0% |
| IS1009b | Mix-Headset | 0.613 | 93.3% | 0.0% |
| IS1009b | Mix-Headset | 0.700 | 74.6% | 0.0% |
| IS1009c | Array1-01 | 0.409 | 96.7% | 3.3% |
| IS1009c | Array1-01 | 0.431 | 96.7% | 3.3% |
| IS1009c | Array1-01 | 0.500 | 96.7% | 3.3% |
| IS1009c | Array1-01 | 0.592 | 96.7% | 3.3% |
| IS1009c | Array1-01 | 0.600 | 95.8% | 3.3% |
| IS1009c | Array1-01 | 0.613 | 95.8% | 3.3% |
| IS1009c | Array1-01 | 0.700 | 79.2% | 1.7% |
| IS1009c | Mix-Headset | 0.409 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.431 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.500 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.592 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.600 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.613 | 98.3% | 1.7% |
| IS1009c | Mix-Headset | 0.700 | 95.8% | 0.0% |

## Identification with averaged probes: enrol from 60 s, identify the mean of k consecutive 6 s windows (second half of the session)

| session | mic | k windows | threshold | correct | false accept | unassigned |
|---|---|---|---|---|---|---|
| ES2004a | Array1-01 | 1 | 0.40 | 92.9% | 7.1% | 0.0% |
| ES2004a | Array1-01 | 1 | 0.50 | 92.9% | 7.1% | 0.0% |
| ES2004a | Array1-01 | 1 | 0.60 | 89.3% | 3.6% | 7.1% |
| ES2004a | Array1-01 | 3 | 0.40 | 94.1% | 5.9% | 0.0% |
| ES2004a | Array1-01 | 3 | 0.50 | 94.1% | 5.9% | 0.0% |
| ES2004a | Array1-01 | 3 | 0.60 | 94.1% | 5.9% | 0.0% |
| ES2004a | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 1 | 0.60 | 98.7% | 0.0% | 1.3% |
| ES2004b | Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 1 | 0.40 | 97.4% | 2.6% | 0.0% |
| ES2004c | Array1-01 | 1 | 0.50 | 97.4% | 2.6% | 0.0% |
| ES2004c | Array1-01 | 1 | 0.60 | 97.4% | 2.6% | 0.0% |
| ES2004c | Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 1 | 0.40 | 94.8% | 5.2% | 0.0% |
| IS1009b | Array1-01 | 1 | 0.50 | 94.8% | 5.2% | 0.0% |
| IS1009b | Array1-01 | 1 | 0.60 | 94.0% | 5.2% | 0.7% |
| IS1009b | Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 1 | 0.60 | 99.3% | 0.0% | 0.7% |
| IS1009b | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 1 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 1 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 1 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c | Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 1 | 0.40 | 99.2% | 0.8% | 0.0% |
| IS1009c | Mix-Headset | 1 | 0.50 | 99.2% | 0.8% | 0.0% |
| IS1009c | Mix-Headset | 1 | 0.60 | 99.2% | 0.8% | 0.0% |
| IS1009c | Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c | Mix-Headset | 5 | 0.60 | 100.0% | 0.0% | 0.0% |

## Across mics with averaged probes: enrol from 60 s on one mic, identify k-window means on the other

| enrol | identify | k | threshold | correct | false accept | unassigned |
|---|---|---|---|---|---|---|
| ES2004a Array1-01 | ES2004a Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 3 | 0.60 | 75.0% | 0.0% | 25.0% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 5 | 0.60 | 81.0% | 0.0% | 19.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 3 | 0.40 | 97.2% | 2.8% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 3 | 0.50 | 97.2% | 2.8% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 3 | 0.60 | 55.6% | 0.0% | 44.4% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 5 | 0.60 | 71.4% | 0.0% | 28.6% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 3 | 0.60 | 70.0% | 0.0% | 30.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 5 | 0.60 | 79.7% | 0.0% | 20.3% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 3 | 0.60 | 77.0% | 0.0% | 23.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 5 | 0.60 | 86.4% | 0.0% | 13.6% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 3 | 0.50 | 99.0% | 0.0% | 1.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 3 | 0.60 | 67.3% | 0.0% | 32.7% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 5 | 0.60 | 75.9% | 0.0% | 24.1% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 3 | 0.60 | 50.0% | 0.0% | 50.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 5 | 0.60 | 72.4% | 0.0% | 27.6% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 3 | 0.40 | 89.3% | 10.7% | 0.0% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 3 | 0.50 | 85.7% | 3.6% | 10.7% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 3 | 0.60 | 64.3% | 0.0% | 35.7% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 5 | 0.40 | 87.5% | 12.5% | 0.0% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 5 | 0.50 | 81.2% | 12.5% | 6.2% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 5 | 0.60 | 62.5% | 0.0% | 37.5% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 3 | 0.40 | 89.3% | 10.7% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 3 | 0.50 | 89.3% | 7.1% | 3.6% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 3 | 0.60 | 89.3% | 7.1% | 3.6% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 5 | 0.40 | 87.5% | 12.5% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 5 | 0.50 | 87.5% | 12.5% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 5 | 0.60 | 87.5% | 6.2% | 6.2% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 3 | 0.50 | 98.9% | 0.0% | 1.1% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 3 | 0.60 | 77.0% | 0.0% | 23.0% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 5 | 0.60 | 84.6% | 0.0% | 15.4% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 3 | 0.50 | 98.9% | 0.0% | 1.1% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 3 | 0.60 | 93.1% | 0.0% | 6.9% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 5 | 0.60 | 98.1% | 0.0% | 1.9% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 3 | 0.60 | 87.0% | 0.0% | 13.0% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 5 | 0.60 | 97.8% | 0.0% | 2.2% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 3 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 3 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 3 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 5 | 0.40 | 100.0% | 0.0% | 0.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 5 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 5 | 0.60 | 100.0% | 0.0% | 0.0% |

## Across sessions with averaged probes: enrol from 30 s in session a (speakers with 24 s or more), identify 30 s means (k=5) in b and c

| enrol | identify | threshold | correct | false accept | unassigned |
|---|---|---|---|---|---|
| ES2004a Array1-01 | ES2004b Array1-01 | 0.45 | 76.3% | 23.7% | 0.0% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.50 | 76.3% | 23.7% | 0.0% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.60 | 76.3% | 23.7% | 0.0% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.45 | 98.3% | 0.0% | 1.7% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.50 | 84.7% | 0.0% | 15.3% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.60 | 64.4% | 0.0% | 35.6% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.45 | 91.4% | 8.6% | 0.0% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.50 | 91.4% | 8.6% | 0.0% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.60 | 91.4% | 8.6% | 0.0% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.45 | 96.6% | 0.0% | 3.4% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.50 | 82.8% | 0.0% | 17.2% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.60 | 44.8% | 0.0% | 55.2% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.45 | 98.3% | 0.0% | 1.7% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.50 | 93.2% | 0.0% | 6.8% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.60 | 50.8% | 0.0% | 49.2% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.45 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.60 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.45 | 93.1% | 0.0% | 6.9% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.50 | 65.5% | 0.0% | 34.5% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.60 | 37.9% | 0.0% | 62.1% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.45 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.50 | 100.0% | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.45 | 96.2% | 3.8% | 0.0% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.50 | 96.2% | 3.8% | 0.0% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.60 | 96.2% | 3.8% | 0.0% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.45 | 94.2% | 5.8% | 0.0% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.50 | 88.5% | 5.8% | 5.8% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.60 | 53.8% | 0.0% | 46.2% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.45 | 100.0% | 0.0% | 0.0% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.45 | 95.7% | 4.3% | 0.0% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.50 | 91.3% | 4.3% | 4.3% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.60 | 65.2% | 4.3% | 30.4% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.45 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.60 | 88.5% | 0.0% | 11.5% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.45 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.45 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.60 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.45 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.50 | 100.0% | 0.0% | 0.0% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.60 | 100.0% | 0.0% | 0.0% |

## Identification across runs: enrol from 20 s in one session, identify 6 s windows elsewhere

| enrol | identify | threshold | correct | false accept |
|---|---|---|---|---|
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.409 | 90.0% | 5.5% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.431 | 85.5% | 3.6% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.500 | 55.5% | 1.8% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.592 | 18.2% | 0.9% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.600 | 15.5% | 0.9% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.613 | 13.6% | 0.9% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.700 | 2.7% | 0.0% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.409 | 82.1% | 17.5% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.431 | 82.1% | 17.5% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.500 | 74.2% | 17.5% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.592 | 65.9% | 14.2% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.600 | 63.9% | 13.9% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.613 | 61.3% | 12.9% |
| ES2004a Array1-01 | ES2004b Array1-01 | 0.700 | 34.1% | 3.6% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.409 | 92.7% | 2.0% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.431 | 87.1% | 1.7% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.500 | 59.3% | 1.0% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.592 | 16.9% | 0.3% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.600 | 15.6% | 0.3% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.613 | 10.6% | 0.0% |
| ES2004a Array1-01 | ES2004b Mix-Headset | 0.700 | 0.7% | 0.0% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.409 | 91.0% | 8.7% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.431 | 91.0% | 8.7% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.500 | 80.0% | 8.7% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.592 | 67.0% | 7.0% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.600 | 64.3% | 6.7% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.613 | 60.0% | 6.0% |
| ES2004a Array1-01 | ES2004c Array1-01 | 0.700 | 26.3% | 1.3% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.409 | 87.3% | 3.3% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.431 | 85.0% | 3.3% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.500 | 56.0% | 0.0% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.592 | 8.7% | 0.0% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.600 | 8.0% | 0.0% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.613 | 4.7% | 0.0% |
| ES2004a Array1-01 | ES2004c Mix-Headset | 0.700 | 0.0% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.409 | 80.9% | 11.8% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.431 | 76.4% | 10.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.500 | 48.2% | 7.3% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.592 | 10.9% | 0.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.600 | 10.0% | 0.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.613 | 10.0% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.700 | 1.8% | 0.0% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.409 | 83.4% | 9.3% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.431 | 78.1% | 9.3% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.500 | 54.0% | 6.6% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.592 | 14.2% | 1.0% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.600 | 12.9% | 1.0% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.613 | 10.6% | 1.0% |
| ES2004a Mix-Headset | ES2004b Array1-01 | 0.700 | 0.7% | 0.0% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.409 | 99.3% | 0.7% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.431 | 99.3% | 0.7% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.500 | 99.0% | 0.7% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.592 | 98.3% | 0.3% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.600 | 98.0% | 0.3% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.613 | 97.7% | 0.3% |
| ES2004a Mix-Headset | ES2004b Mix-Headset | 0.700 | 85.8% | 0.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.409 | 72.7% | 2.3% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.431 | 60.3% | 2.3% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.500 | 35.7% | 1.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.592 | 16.3% | 0.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.600 | 15.3% | 0.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.613 | 12.3% | 0.0% |
| ES2004a Mix-Headset | ES2004c Array1-01 | 0.700 | 2.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.409 | 100.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.431 | 100.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.500 | 100.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.592 | 99.7% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.600 | 99.3% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.613 | 99.0% | 0.0% |
| ES2004a Mix-Headset | ES2004c Mix-Headset | 0.700 | 73.3% | 0.0% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.409 | 89.1% | 10.9% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.431 | 89.1% | 10.9% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.500 | 87.3% | 10.9% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.592 | 71.8% | 5.5% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.600 | 67.3% | 3.6% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.613 | 62.7% | 1.8% |
| ES2004b Array1-01 | ES2004a Array1-01 | 0.700 | 30.0% | 0.0% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.409 | 60.0% | 18.2% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.431 | 54.5% | 12.7% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.500 | 29.1% | 5.5% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.592 | 2.7% | 0.0% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.600 | 2.7% | 0.0% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.613 | 1.8% | 0.0% |
| ES2004b Array1-01 | ES2004a Mix-Headset | 0.700 | 0.0% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.409 | 78.1% | 12.9% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.431 | 74.2% | 10.9% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.500 | 49.7% | 2.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.592 | 17.5% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.600 | 14.2% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.613 | 9.6% | 0.0% |
| ES2004b Array1-01 | ES2004b Mix-Headset | 0.700 | 0.7% | 0.0% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.409 | 93.7% | 6.3% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.431 | 93.7% | 6.3% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.500 | 93.3% | 6.3% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.592 | 84.7% | 3.0% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.600 | 83.0% | 3.0% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.613 | 79.7% | 2.7% |
| ES2004b Array1-01 | ES2004c Array1-01 | 0.700 | 42.3% | 0.7% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.409 | 69.0% | 14.0% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.431 | 64.3% | 8.3% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.500 | 36.0% | 1.0% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.592 | 1.3% | 0.0% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.600 | 1.3% | 0.0% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.613 | 0.7% | 0.0% |
| ES2004b Array1-01 | ES2004c Mix-Headset | 0.700 | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.409 | 67.3% | 16.4% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.431 | 61.8% | 13.6% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.500 | 42.7% | 6.4% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.592 | 10.0% | 0.0% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.600 | 8.2% | 0.0% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.613 | 8.2% | 0.0% |
| ES2004b Mix-Headset | ES2004a Array1-01 | 0.700 | 0.9% | 0.0% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.409 | 76.4% | 23.6% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.431 | 76.4% | 23.6% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.500 | 73.6% | 22.7% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.592 | 64.5% | 7.3% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.600 | 63.6% | 5.5% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.613 | 61.8% | 3.6% |
| ES2004b Mix-Headset | ES2004a Mix-Headset | 0.700 | 50.0% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.409 | 83.4% | 10.3% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.431 | 81.5% | 8.6% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.500 | 63.2% | 5.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.592 | 17.9% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.600 | 14.9% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.613 | 8.6% | 0.0% |
| ES2004b Mix-Headset | ES2004b Array1-01 | 0.700 | 0.0% | 0.0% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.409 | 86.7% | 4.0% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.431 | 81.3% | 3.7% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.500 | 51.3% | 1.0% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.592 | 9.3% | 0.3% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.600 | 8.3% | 0.0% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.613 | 4.7% | 0.0% |
| ES2004b Mix-Headset | ES2004c Array1-01 | 0.700 | 0.3% | 0.0% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.409 | 79.3% | 20.7% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.431 | 79.3% | 20.7% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.500 | 79.3% | 20.3% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.592 | 77.7% | 7.3% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.600 | 77.3% | 5.7% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.613 | 75.3% | 2.0% |
| ES2004b Mix-Headset | ES2004c Mix-Headset | 0.700 | 60.0% | 0.0% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.409 | 89.1% | 10.9% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.431 | 89.1% | 10.9% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.500 | 89.1% | 10.9% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.592 | 84.5% | 6.4% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.600 | 82.7% | 4.5% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.613 | 79.1% | 3.6% |
| ES2004c Array1-01 | ES2004a Array1-01 | 0.700 | 52.7% | 0.0% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.409 | 97.3% | 2.7% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.431 | 96.4% | 1.8% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.500 | 70.0% | 1.8% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.592 | 16.4% | 0.9% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.600 | 13.6% | 0.0% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.613 | 11.8% | 0.0% |
| ES2004c Array1-01 | ES2004a Mix-Headset | 0.700 | 0.9% | 0.0% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.409 | 94.4% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.431 | 94.4% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.500 | 94.4% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.592 | 93.0% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.600 | 92.7% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.613 | 91.7% | 5.6% |
| ES2004c Array1-01 | ES2004b Array1-01 | 0.700 | 65.2% | 1.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.409 | 99.0% | 1.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.431 | 98.3% | 1.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.500 | 86.1% | 0.7% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.592 | 21.9% | 0.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.600 | 16.6% | 0.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.613 | 13.6% | 0.0% |
| ES2004c Array1-01 | ES2004b Mix-Headset | 0.700 | 0.3% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.409 | 99.3% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.431 | 97.7% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.500 | 83.3% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.592 | 11.0% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.600 | 8.7% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.613 | 5.0% | 0.0% |
| ES2004c Array1-01 | ES2004c Mix-Headset | 0.700 | 0.0% | 0.0% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.409 | 89.1% | 2.7% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.431 | 84.5% | 2.7% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.500 | 61.8% | 0.9% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.592 | 22.7% | 0.9% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.600 | 18.2% | 0.0% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.613 | 17.3% | 0.0% |
| ES2004c Mix-Headset | ES2004a Array1-01 | 0.700 | 1.8% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.409 | 100.0% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.431 | 100.0% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.500 | 100.0% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.592 | 95.5% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.600 | 95.5% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.613 | 93.6% | 0.0% |
| ES2004c Mix-Headset | ES2004a Mix-Headset | 0.700 | 78.2% | 0.0% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.409 | 95.0% | 3.0% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.431 | 94.0% | 3.0% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.500 | 75.5% | 2.3% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.592 | 23.8% | 0.7% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.600 | 20.9% | 0.7% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.613 | 17.5% | 0.7% |
| ES2004c Mix-Headset | ES2004b Array1-01 | 0.700 | 1.0% | 0.0% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.409 | 99.3% | 0.7% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.431 | 99.3% | 0.7% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.500 | 99.0% | 0.3% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.592 | 98.7% | 0.3% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.600 | 98.3% | 0.3% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.613 | 98.0% | 0.3% |
| ES2004c Mix-Headset | ES2004b Mix-Headset | 0.700 | 90.1% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.409 | 98.7% | 0.3% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.431 | 98.3% | 0.3% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.500 | 76.0% | 0.3% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.592 | 28.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.600 | 24.3% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.613 | 18.0% | 0.0% |
| ES2004c Mix-Headset | ES2004c Array1-01 | 0.700 | 2.3% | 0.0% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.409 | 98.9% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.431 | 98.9% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.500 | 90.8% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.592 | 66.7% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.600 | 63.2% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.613 | 51.7% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.700 | 21.8% | 0.0% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.409 | 95.9% | 3.7% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.431 | 95.9% | 3.7% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.500 | 95.9% | 3.7% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.592 | 94.4% | 3.7% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.600 | 92.9% | 3.4% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.613 | 92.5% | 3.4% |
| IS1009a Array1-01 | IS1009b Array1-01 | 0.700 | 76.0% | 0.4% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.409 | 91.4% | 8.6% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.431 | 90.6% | 8.2% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.500 | 71.5% | 6.4% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.592 | 31.8% | 1.9% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.600 | 28.8% | 1.9% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.613 | 22.1% | 1.1% |
| IS1009a Array1-01 | IS1009b Mix-Headset | 0.700 | 2.2% | 0.0% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.409 | 98.3% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.431 | 98.3% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.500 | 98.3% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.592 | 96.6% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.600 | 95.4% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.613 | 95.4% | 1.7% |
| IS1009a Array1-01 | IS1009c Array1-01 | 0.700 | 72.2% | 0.8% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.409 | 69.6% | 27.8% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.431 | 67.9% | 27.8% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.500 | 61.6% | 22.4% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.592 | 31.2% | 3.8% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.600 | 27.4% | 3.0% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.613 | 24.1% | 2.1% |
| IS1009a Array1-01 | IS1009c Mix-Headset | 0.700 | 1.7% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.409 | 98.9% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.431 | 98.9% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.500 | 95.4% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.592 | 73.6% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.600 | 70.1% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.613 | 63.2% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.700 | 34.5% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.409 | 97.4% | 1.1% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.431 | 97.0% | 1.1% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.500 | 93.3% | 0.7% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.592 | 68.9% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.600 | 65.5% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.613 | 62.2% | 0.0% |
| IS1009a Mix-Headset | IS1009b Array1-01 | 0.700 | 21.3% | 0.0% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.409 | 98.1% | 1.9% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.431 | 98.1% | 1.9% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.500 | 98.1% | 1.5% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.592 | 96.3% | 1.1% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.600 | 95.5% | 1.1% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.613 | 95.1% | 1.1% |
| IS1009a Mix-Headset | IS1009b Mix-Headset | 0.700 | 88.0% | 0.7% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.409 | 99.2% | 0.4% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.431 | 98.7% | 0.4% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.500 | 95.4% | 0.4% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.592 | 75.5% | 0.4% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.600 | 71.3% | 0.4% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.613 | 68.4% | 0.0% |
| IS1009a Mix-Headset | IS1009c Array1-01 | 0.700 | 23.6% | 0.0% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.409 | 99.6% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.431 | 99.6% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.500 | 99.6% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.592 | 99.2% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.600 | 99.2% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.613 | 99.2% | 0.4% |
| IS1009a Mix-Headset | IS1009c Mix-Headset | 0.700 | 87.3% | 0.0% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.409 | 95.4% | 4.6% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.431 | 95.4% | 4.6% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.500 | 95.4% | 4.6% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.592 | 81.6% | 3.4% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.600 | 77.0% | 3.4% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.613 | 73.6% | 3.4% |
| IS1009b Array1-01 | IS1009a Array1-01 | 0.700 | 55.2% | 0.0% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.409 | 83.9% | 9.2% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.431 | 78.2% | 9.2% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.500 | 48.3% | 1.1% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.592 | 18.4% | 1.1% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.600 | 14.9% | 0.0% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.613 | 12.6% | 0.0% |
| IS1009b Array1-01 | IS1009a Mix-Headset | 0.700 | 2.3% | 0.0% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.409 | 67.8% | 9.7% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.431 | 57.7% | 8.6% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.500 | 32.6% | 3.4% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.592 | 20.2% | 1.9% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.600 | 19.9% | 1.9% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.613 | 19.9% | 1.5% |
| IS1009b Array1-01 | IS1009b Mix-Headset | 0.700 | 7.5% | 0.0% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.409 | 94.5% | 5.5% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.431 | 94.5% | 5.5% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.500 | 94.5% | 5.5% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.592 | 89.9% | 4.6% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.600 | 89.0% | 4.6% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.613 | 86.1% | 4.6% |
| IS1009b Array1-01 | IS1009c Array1-01 | 0.700 | 47.7% | 0.4% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.409 | 73.4% | 8.9% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.431 | 67.9% | 8.0% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.500 | 36.7% | 1.3% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.592 | 20.7% | 0.0% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.600 | 19.8% | 0.0% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.613 | 18.1% | 0.0% |
| IS1009b Array1-01 | IS1009c Mix-Headset | 0.700 | 2.1% | 0.0% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.409 | 93.1% | 5.7% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.431 | 93.1% | 5.7% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.500 | 93.1% | 5.7% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.592 | 86.2% | 2.3% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.600 | 83.9% | 2.3% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.613 | 83.9% | 2.3% |
| IS1009b Mix-Headset | IS1009a Array1-01 | 0.700 | 52.9% | 2.3% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.409 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.431 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.500 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.592 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.600 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.613 | 98.9% | 1.1% |
| IS1009b Mix-Headset | IS1009a Mix-Headset | 0.700 | 92.0% | 1.1% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.409 | 94.0% | 5.6% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.431 | 94.0% | 5.6% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.500 | 89.5% | 4.5% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.592 | 74.9% | 0.7% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.600 | 73.0% | 0.7% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.613 | 71.9% | 0.7% |
| IS1009b Mix-Headset | IS1009b Array1-01 | 0.700 | 45.3% | 0.0% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.409 | 95.8% | 4.2% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.431 | 95.8% | 4.2% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.500 | 94.1% | 3.4% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.592 | 77.2% | 2.1% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.600 | 74.3% | 2.1% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.613 | 67.9% | 1.7% |
| IS1009b Mix-Headset | IS1009c Array1-01 | 0.700 | 38.0% | 0.4% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.409 | 98.7% | 1.3% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.431 | 98.7% | 1.3% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.500 | 98.7% | 1.3% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.592 | 97.0% | 1.3% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.600 | 96.6% | 1.3% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.613 | 95.4% | 0.8% |
| IS1009b Mix-Headset | IS1009c Mix-Headset | 0.700 | 75.1% | 0.0% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.409 | 94.3% | 5.7% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.431 | 94.3% | 5.7% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.500 | 94.3% | 4.6% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.592 | 94.3% | 4.6% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.600 | 94.3% | 4.6% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.613 | 92.0% | 4.6% |
| IS1009c Array1-01 | IS1009a Array1-01 | 0.700 | 74.7% | 2.3% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.409 | 86.2% | 13.8% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.431 | 85.1% | 13.8% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.500 | 82.8% | 12.6% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.592 | 41.4% | 6.9% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.600 | 39.1% | 5.7% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.613 | 33.3% | 5.7% |
| IS1009c Array1-01 | IS1009a Mix-Headset | 0.700 | 10.3% | 1.1% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.409 | 92.9% | 6.7% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.431 | 92.9% | 6.7% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.500 | 92.9% | 6.7% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.592 | 92.1% | 6.7% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.600 | 91.8% | 6.7% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.613 | 90.6% | 6.4% |
| IS1009c Array1-01 | IS1009b Array1-01 | 0.700 | 79.4% | 2.2% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.409 | 89.9% | 9.0% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.431 | 88.0% | 9.0% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.500 | 74.5% | 4.9% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.592 | 43.1% | 1.9% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.600 | 39.0% | 1.5% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.613 | 34.8% | 1.1% |
| IS1009c Array1-01 | IS1009b Mix-Headset | 0.700 | 15.0% | 0.4% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.409 | 94.1% | 5.9% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.431 | 92.4% | 5.9% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.500 | 74.3% | 4.6% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.592 | 40.5% | 2.1% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.600 | 38.8% | 1.7% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.613 | 36.3% | 1.3% |
| IS1009c Array1-01 | IS1009c Mix-Headset | 0.700 | 18.6% | 0.0% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.409 | 87.4% | 11.5% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.431 | 87.4% | 11.5% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.500 | 81.6% | 11.5% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.592 | 65.5% | 5.7% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.600 | 60.9% | 5.7% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.613 | 57.5% | 3.4% |
| IS1009c Mix-Headset | IS1009a Array1-01 | 0.700 | 21.8% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.409 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.431 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.500 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.592 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.600 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.613 | 98.9% | 1.1% |
| IS1009c Mix-Headset | IS1009a Mix-Headset | 0.700 | 93.1% | 1.1% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.409 | 96.3% | 3.0% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.431 | 95.5% | 2.6% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.500 | 86.9% | 2.6% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.592 | 59.6% | 1.5% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.600 | 58.1% | 1.5% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.613 | 53.9% | 1.1% |
| IS1009c Mix-Headset | IS1009b Array1-01 | 0.700 | 20.6% | 0.0% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.409 | 99.3% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.431 | 99.3% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.500 | 99.3% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.592 | 97.8% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.600 | 97.8% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.613 | 97.0% | 0.7% |
| IS1009c Mix-Headset | IS1009b Mix-Headset | 0.700 | 90.3% | 0.4% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.409 | 95.4% | 4.6% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.431 | 95.4% | 4.6% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.500 | 91.6% | 3.8% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.592 | 75.9% | 3.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.600 | 72.2% | 3.0% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.613 | 67.5% | 2.5% |
| IS1009c Mix-Headset | IS1009c Array1-01 | 0.700 | 32.1% | 0.4% |
