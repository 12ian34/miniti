#!/usr/bin/env python
"""Offline Nemotron with raw frame probabilities, then a binarisation-threshold sweep scored against the references.
Shows the missed vs false-alarm operating points available without touching the model."""
import glob, json, os, sys
import numpy as np, torch
from pyannote.core import Annotation, Segment
from pyannote.database.util import load_rttm
from pyannote.metrics.diarization import DiarizationErrorRate
from nemo.collections.asr.models import SortformerEncLabelModel

files = sorted(glob.glob('data/*.16k.wav'))
model = SortformerEncLabelModel.from_pretrained('nvidia/Nemotron-3-Diarization', map_location='cpu').eval()
m = model.sortformer_modules
m.spkcache_len, m.fifo_len, m.chunk_len, m.chunk_right_context, m.spkcache_update_period = 264, 40, 340, 40, 300
model._check_streaming_parameters()
segs, probs = model.diarize(audio=files, batch_size=1, include_tensor_outputs=True, verbose=False)

def to_annotation(p, thr, stride_s, uri, min_dur=0.0):
    ann = Annotation(uri=uri)
    act = (p >= thr)
    for k in range(act.shape[1]):
        on = None
        for t in range(act.shape[0] + 1):
            v = act[t, k] if t < act.shape[0] else False
            if v and on is None: on = t
            if not v and on is not None:
                if (t - on) * stride_s >= min_dur: ann[Segment(on * stride_s, t * stride_s)] = f'spk{k}'
                on = None
    return ann

rows = []
for path, p in zip(files, probs):
    tag = os.path.basename(path).replace('.16k.wav', '')
    meeting, ch = tag.split('.')
    ref = load_rttm(f'data/{meeting}.rttm')[meeting]
    import wave
    with wave.open(path) as w: dur = w.getnframes() / w.getframerate()
    p = p.detach().cpu().numpy()
    while p.ndim > 2: p = p[0]
    stride = dur / p.shape[0]
    np.save(f'out/nemotron-probs-{tag}.npy', p)
    for thr in [0.3, 0.4, 0.5, 0.6, 0.7]:
        hyp = to_annotation(p, thr, stride, meeting)
        for name, kw in [('collar', dict(collar=0.25, skip_overlap=False)), ('nooverlap', dict(collar=0.25, skip_overlap=True))]:
            det = DiarizationErrorRate(**kw)(ref, hyp, detailed=True)
            tot = det['total'] or 1
            rows.append({'file': tag, 'thr': thr, 'metric': name, 'der': det['diarization error rate'], 'missed': det['missed detection'] / tot, 'fa': det['false alarm'] / tot, 'conf': det['confusion'] / tot, 'spk': len(hyp.labels())})
json.dump({'stride_s': stride, 'rows': rows}, open('out/threshold-sweep.json', 'w'), indent=1)
print(f'frame stride {stride*1000:.1f} ms')
print('| file | threshold | DER (collar) | missed | false alarm | confusion | DER (overlap excluded) | speakers |')
print('|---|---|---|---|---|---|---|---|')
for tag in sorted({r['file'] for r in rows}):
    for thr in [0.3, 0.4, 0.5, 0.6, 0.7]:
        a = next(r for r in rows if r['file'] == tag and r['thr'] == thr and r['metric'] == 'collar')
        b = next(r for r in rows if r['file'] == tag and r['thr'] == thr and r['metric'] == 'nooverlap')
        print(f"| {tag} | {thr} | {a['der']*100:.1f}% | {a['missed']*100:.1f}% | {a['fa']*100:.1f}% | {a['conf']*100:.1f}% | {b['der']*100:.1f}% | {a['spk']} |")
