# Voice print POC (2026-10-18)

Does the CAM++ speaker embedding in FluidAudio 0.17.4 (the package miniti ships) recognise the same person across meetings and microphones? Feeds `docs/voice-prints-plan.md`. Nothing in the app changed.

- `fetch.sh`: AMI ES2004a/b/c and IS1009a/b/c (the same four people per series), headset mix and far-field array mic at 16 kHz, plus pyannote `only_words` RTTMs. Reuses the diarization spike's files. `data/` is gitignored.
- `harness/`: Swift package. `harness <rttm> <wav> <out.json>` embeds 6 s windows of each reference speaker's non-overlapping speech. First run downloads the CAM++ models (two Core ML stages) into FluidAudio's model directory.
- `score.py`: same versus different speaker similarities within a session, across sessions, across mics; equal error rate; identification accuracy after enrolling from 20 s. Needs numpy.
- `run_all.sh`: fetch, build, embed everything, score into `RESULTS.md`.
