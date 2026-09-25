#!/usr/bin/env python
"""Nemotron-3-Diarization through Transformers (offline mode), writing RTTMs plus timing.
  .venv-hf/bin/python run_nemotron_hf.py --device cpu data/ES2004a.Array1-01.16k.wav
"""
import argparse, json, os, time, wave
import torch, soundfile as sf
from transformers import AutoModelForAudioFrameClassification, AutoProcessor

ap = argparse.ArgumentParser()
ap.add_argument('files', nargs='+')
ap.add_argument('--device', default='cpu')
ap.add_argument('--mode', default='offline', choices=['offline', 'low_latency', 'very_low_latency', 'ultra_low_latency'])
ap.add_argument('--out', default='out')
a = ap.parse_args()

mid = 'nvidia/Nemotron-3-Diarization'
t0 = time.time()
processor = AutoProcessor.from_pretrained(mid)
model = AutoModelForAudioFrameClassification.from_pretrained(mid).to(a.device).eval()
load_s = time.time() - t0
print(f'loaded in {load_s:.1f}s on {a.device}; streaming modes available: {getattr(processor, "set_streaming_mode", None) is not None}', flush=True)
sr = processor.feature_extractor.sampling_rate
os.makedirs(a.out, exist_ok=True)
for path in a.files:
    audio, file_sr = sf.read(path, dtype='float32')
    assert file_sr == sr, (file_sr, sr)
    dur = len(audio) / sr
    tag = os.path.basename(path).replace('.16k.wav', '')
    t1 = time.time()
    with torch.inference_mode():
        if a.mode == 'offline':
            inputs = processor(audio, sampling_rate=sr, return_tensors='pt').to(a.device)
            logits = model(**inputs).logits
            segments = processor.extract_speaker_dict(logits.cpu(), inputs.get('attention_mask', None).cpu() if inputs.get('attention_mask', None) is not None else None)[0]
        else:
            processor.set_streaming_mode(a.mode)
            cache, chunks = None, []
            for inputs in processor.streaming_inputs(audio, sampling_rate=sr) if hasattr(processor, 'streaming_inputs') else processor.iter_streaming_inputs(audio, sampling_rate=sr):
                inputs = inputs.to(a.device)
                out = model(**inputs, speaker_cache=cache)
                chunks.append(out.logits.cpu()); cache = out.speaker_cache
            segments = processor.extract_speaker_dict(torch.cat(chunks, dim=1))[0]
    elapsed = time.time() - t1
    rttm = os.path.join(a.out, f'nemotron-{a.mode}-hf{a.device}-{tag}.rttm')
    spk = set()
    with open(rttm, 'w') as f:
        for s in segments:
            spk.add(s['Speaker'])
            f.write(f"SPEAKER {tag} 1 {s['Start']:.3f} {s['End'] - s['Start']:.3f} <NA> <NA> spk{s['Speaker']} <NA> <NA>\n")
    timing = {'file': tag, 'mode': a.mode, 'device': f'hf{a.device}', 'audio_s': dur, 'elapsed_s': elapsed, 'rtf': elapsed / dur, 'speakers': len(spk), 'segments': len(segments), 'load_s': load_s}
    json.dump(timing, open(rttm.replace('.rttm', '.timing.json'), 'w'))
    print(json.dumps(timing), flush=True)
