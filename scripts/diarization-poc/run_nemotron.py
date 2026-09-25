#!/usr/bin/env python
"""Run nvidia/Nemotron-3-Diarization on 16 kHz mono wavs and write RTTMs plus timing.

  .venv/bin/python run_nemotron.py --mode offline --device cpu data/ES2004a.Array1-01.16k.wav
  modes: offline (30.4 s window), low (1.04 s latency), verylow (0.64 s), ultra (0.32 s)
Streaming modes use the model card's recommended cache/FIFO/chunk settings (values in 80 ms frames).
"""
import argparse, json, os, sys, time, wave

import torch

MODES = {  # spkcache_len, fifo_len, chunk_len, chunk_right_context, spkcache_update_period
    'offline': (264, 40, 340, 40, 300),
    'low': (264, 264, 9, 4, 222),
    'verylow': (264, 264, 6, 2, 222),
    'ultra': (264, 264, 3, 1, 222),
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--mode', default='offline', choices=MODES)
    ap.add_argument('--device', default='cpu')
    ap.add_argument('--out', default='out')
    a = ap.parse_args()

    from nemo.collections.asr.models import SortformerEncLabelModel
    t0 = time.time()
    model = SortformerEncLabelModel.from_pretrained('nvidia/Nemotron-3-Diarization', map_location=a.device)
    model.eval()
    sc, fifo, chunk, rc, upd = MODES[a.mode]
    m = model.sortformer_modules
    m.spkcache_len, m.fifo_len, m.chunk_len, m.chunk_right_context, m.spkcache_update_period = sc, fifo, chunk, rc, upd
    model._check_streaming_parameters()
    load_s = time.time() - t0
    print(f'loaded in {load_s:.1f}s on {a.device}, mode={a.mode}', flush=True)

    os.makedirs(a.out, exist_ok=True)
    for path in a.files:
        with wave.open(path) as w:
            dur = w.getnframes() / w.getframerate()
        tag = os.path.basename(path).replace('.16k.wav', '')
        t1 = time.time()
        segs = model.diarize(audio=[path], batch_size=1)[0]
        elapsed = time.time() - t1
        rttm = os.path.join(a.out, f'nemotron-{a.mode}-{a.device}-{tag}.rttm')
        n_spk = set()
        with open(rttm, 'w') as f:
            for s in segs:
                b, e, spk = s.split()
                b, e = float(b), float(e)
                n_spk.add(spk)
                f.write(f'SPEAKER {tag} 1 {b:.3f} {e - b:.3f} <NA> <NA> spk{spk} <NA> <NA>\n')
        timing = {'file': tag, 'mode': a.mode, 'device': a.device, 'audio_s': dur, 'elapsed_s': elapsed, 'rtf': elapsed / dur, 'speakers': len(n_spk), 'segments': len(segs), 'load_s': load_s}
        with open(os.path.join(a.out, f'nemotron-{a.mode}-{a.device}-{tag}.timing.json'), 'w') as f:
            json.dump(timing, f)
        print(json.dumps(timing), flush=True)

if __name__ == '__main__':
    main()
