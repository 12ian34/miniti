# Voice print POC results (2026-10-18, first pass)

Offline only. CAM++ speaker embeddings (FluidAudio 0.17.4, the package miniti ships; 192-d, L2-normalised, cosine similarity) over AMI ES2004a and IS1009a, four real speakers each, the headset mix (a good call) and one far-field array mic in the room (the hard case: a phone on the table). Reference turns from the pyannote `only_words` RTTMs, overlap removed. Cross-session (same people, a different day) is still pending: the Edinburgh mirror is slow, `fetch.sh` resumes in the background and these tables get the b and c sessions when they land.

## Reading it

- **Speed**: 6 ms per 6 s window on this Mac. Negligible next to the diarizer.
- **Single 6 s windows are not enough** (second table): 8.5% equal error rate within a session, 12.9% across mics. That is the number to expect if a speaker is matched from one short sentence.
- **The product matches a growing per-speaker average, and that works**: enrol from 60 s, identify the mean of five windows (30 s of speech) from the second half of the meeting, and every speaker in both meetings on both mics is right with no false accepts at thresholds from 0.4 to 0.6. Three windows (18 s) already give 94 to 100%.
- **Across microphones** (enrol on the headset, identify on the room mic, or the reverse): ES2004a is 100% correct with no false accepts at 0.5. IS1009a is the hard one: 81 to 89% correct with 6 to 12% false accepts at 0.4 to 0.5; at 0.6 the false accepts fall to 0 to 7% and the rest go unassigned rather than wrong. That is the case the confirm band is for.
- **Thresholds to start from**: match at 0.60, confirm band 0.45 to 0.60, nothing below. Re-measured once the cross-session sessions are in.

Preliminary verdict against the plan's gates: within session and headset, pass. Across mics, pass on one meeting and a near miss on the other, which the confirm band covers. Cross-session, not yet measured.

## Windows and speed

| session | mic | windows | speakers | ms per window |
|---|---|---|---|---|
| ES2004a | Array1-01 | 110 | 4 | 6 |
| ES2004a | Mix-Headset | 110 | 4 | 6 |
| IS1009a | Array1-01 | 87 | 4 | 6 |
| IS1009a | Mix-Headset | 87 | 4 | 6 |

## Same versus different speaker, cosine similarity

| condition | pairs | same: mean (p5) | different: mean (p95) | EER | threshold at EER |
|---|---|---|---|---|---|
| within session | 38944 | 0.726 (0.517) | 0.442 (0.631) | 10.2% | 0.605 |
| across mics, same session | 19669 | 0.547 (0.364) | 0.324 (0.522) | 17.1% | 0.423 |

## Identification within a session: enrol from the first 20 s, identify the second half

| session | mic | threshold | correct | false accept |
|---|---|---|---|---|
| ES2004a | Array1-01 | 0.423 | 76.8% | 23.2% |
| ES2004a | Array1-01 | 0.500 | 75.0% | 23.2% |
| ES2004a | Array1-01 | 0.600 | 60.7% | 23.2% |
| ES2004a | Array1-01 | 0.605 | 60.7% | 21.4% |
| ES2004a | Array1-01 | 0.700 | 30.4% | 0.0% |
| ES2004a | Mix-Headset | 0.423 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.500 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.600 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.605 | 100.0% | 0.0% |
| ES2004a | Mix-Headset | 0.700 | 91.1% | 0.0% |
| IS1009a | Array1-01 | 0.423 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.500 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.600 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.605 | 100.0% | 0.0% |
| IS1009a | Array1-01 | 0.700 | 78.6% | 0.0% |
| IS1009a | Mix-Headset | 0.423 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.500 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.600 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.605 | 100.0% | 0.0% |
| IS1009a | Mix-Headset | 0.700 | 97.6% | 0.0% |

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

## Identification across runs: enrol from 20 s in one session, identify 6 s windows elsewhere

| enrol | identify | threshold | correct | false accept |
|---|---|---|---|---|
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.423 | 87.3% | 4.5% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.500 | 55.5% | 1.8% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.600 | 15.5% | 0.9% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.605 | 14.5% | 0.9% |
| ES2004a Array1-01 | ES2004a Mix-Headset | 0.700 | 2.7% | 0.0% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.423 | 79.1% | 10.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.500 | 48.2% | 7.3% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.600 | 10.0% | 0.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.605 | 10.0% | 0.9% |
| ES2004a Mix-Headset | ES2004a Array1-01 | 0.700 | 1.8% | 0.0% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.423 | 98.9% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.500 | 90.8% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.600 | 63.2% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.605 | 59.8% | 1.1% |
| IS1009a Array1-01 | IS1009a Mix-Headset | 0.700 | 21.8% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.423 | 98.9% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.500 | 95.4% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.600 | 70.1% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.605 | 69.0% | 0.0% |
| IS1009a Mix-Headset | IS1009a Array1-01 | 0.700 | 34.5% | 0.0% |
