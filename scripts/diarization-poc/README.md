# Diarization POC: nvidia/Nemotron-3-Diarization vs Deepgram nova-3

Offline evaluation of NVIDIA's Nemotron-3-Diarization (100M-parameter Sortformer, streaming-capable, up to 8 speakers)
against the Deepgram diarization miniti uses today, on two AMI meeting-corpus test meetings with public reference labels.
Results and the integration assessment are in [RESULTS.md](RESULTS.md).

## Layout

- `fetch_and_deepgram.sh`: downloads the AMI audio (headset mix and single far-field array mic for ES2004a and IS1009a), converts to 16 kHz mono, runs Deepgram prerecorded diarization (`diarize=true`).
- `deepgram_stream.py`: streams the same audio over Deepgram's live WebSocket with the exact query parameters from `DeepgramService.swift`, which is the path the app actually uses.
- `run_nemotron.py`: runs Nemotron through NeMo in offline (30.4 s window) or streaming (1.04 s / 0.64 s / 0.32 s latency) mode, on CPU or MPS, and writes RTTMs plus timing.
- `run_nemotron_hf.py`: same through Transformers (needs transformers from source as of 2026-09-25; written but not verified end to end, the NeMo path is the one used for the numbers).
- `sweep_thresholds.py`: binarisation-threshold sweep over Nemotron's raw frame probabilities.
- `score.py`: DER (pyannote.metrics, 0.25 s collar, overlap included; plus no-collar and overlap-excluded variants) for everything in `out/`.
- `data/`: audio and reference RTTMs (gitignored). References come from `github.com/pyannote/AMI-diarization-setup` (`only_words`).
- `out/`: hypotheses, timings, scores (gitignored).

## Setup

```
~/.local/bin/uv venv --python 3.12 .venv
~/.local/bin/uv pip install --python .venv/bin/python Cython packaging pyannote.metrics requests websockets \
  "nemo-toolkit[asr] @ git+https://github.com/NVIDIA/NeMo.git"
./fetch_and_deepgram.sh
.venv/bin/python deepgram_stream.py data/*.16k.wav
.venv/bin/python run_nemotron.py --mode offline --device cpu data/*.16k.wav
.venv/bin/python run_nemotron.py --mode low --device cpu data/*.16k.wav
.venv/bin/python score.py
```

The released NeMo 3.0.0 cannot load the model (`self_attention_model='rope' is not supported`); GitHub main works.
Transformers 5.17 does not know `nemotron3_diarization` either; source install works. The Deepgram key is read from
`../../../miniti-api/.env`.
