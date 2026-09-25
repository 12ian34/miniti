#!/usr/bin/env python
"""Score every hypothesis RTTM/JSON in out/ against the AMI reference RTTMs in data/.

DER via pyannote.metrics (standard 0.25 s collar, overlap included) plus a no-collar figure,
speaker-count error, and the missed / false-alarm / confusion split.
"""
import glob, json, os, re
from pyannote.core import Annotation, Segment
from pyannote.database.util import load_rttm
from pyannote.metrics.diarization import DiarizationErrorRate

def deepgram_to_annotation(path, uri):
    d = json.load(open(path))
    words = d['results']['channels'][0]['alternatives'][0]['words']
    ann = Annotation(uri=uri)
    # merge consecutive words of the same speaker with gaps under 0.5 s into one segment
    cur = None
    for w in words:
        spk = f"dg{w.get('speaker', 0)}"
        if cur and cur[2] == spk and w['start'] - cur[1] < 0.5:
            cur[1] = w['end']
        else:
            if cur: ann[Segment(cur[0], cur[1])] = cur[2]
            cur = [w['start'], w['end'], spk]
    if cur: ann[Segment(cur[0], cur[1])] = cur[2]
    return ann

def load_ref(meeting):
    return load_rttm(f'data/{meeting}.rttm')[meeting]

def score(ref, hyp):
    out = {}
    for collar, skip, key in [(0.25, False, 'der_collar'), (0.0, False, 'der_nocollar'), (0.25, True, 'der_nooverlap')]:
        m = DiarizationErrorRate(collar=collar, skip_overlap=skip)
        det = m(ref, hyp, detailed=True)
        out[key] = det['diarization error rate']
        if collar == 0.25 and not skip:
            tot = det['total'] or 1
            out.update(missed=det['missed detection'] / tot, false_alarm=det['false alarm'] / tot, confusion=det['confusion'] / tot)
    out['ref_speakers'] = len(ref.labels())
    out['hyp_speakers'] = len(hyp.labels())
    return out

rows = []
for p in sorted(glob.glob('out/deepgram-*.json')):
    m = re.match(r'out/deepgram-(\w+)-(ES\d+\w|IS\d+\w)\.(.+)\.json', p)
    kind, meeting, ch = m.groups()
    ref = load_ref(meeting)
    hyp = deepgram_to_annotation(p, meeting)
    rows.append({'system': f'deepgram nova-3 {kind}', 'meeting': meeting, 'channel': ch, **score(ref, hyp)})
for p in sorted(glob.glob('out/nemotron-*.rttm')):
    m = re.match(r'out/nemotron-(\w+)-(\w+)-(ES\d+\w|IS\d+\w)\.(.+)\.rttm', p)
    mode, device, meeting, ch = m.groups()
    ref = load_ref(meeting)
    tag = f'{meeting}.{ch}'
    hyp = load_rttm(p).get(tag, Annotation(uri=tag))
    hyp.uri = meeting
    t = json.load(open(p.replace('.rttm', '.timing.json'))) if os.path.exists(p.replace('.rttm', '.timing.json')) else {}
    rows.append({'system': f'nemotron-3 {mode} ({device})', 'meeting': meeting, 'channel': ch, **score(ref, hyp), 'rtf': t.get('rtf')})

json.dump(rows, open('out/scores.json', 'w'), indent=1)
print('| system | meeting | channel | DER (0.25 s collar) | DER (no collar) | DER (overlap excluded) | missed | false alarm | confusion | speakers ref/hyp | RTF |')
print('|---|---|---|---|---|---|---|---|---|---|---|')
for r in sorted(rows, key=lambda r: (r['meeting'], r['channel'], r['system'])):
    print(f"| {r['system']} | {r['meeting']} | {r['channel']} | {r['der_collar']*100:.1f}% | {r['der_nocollar']*100:.1f}% | {r['der_nooverlap']*100:.1f}% | {r['missed']*100:.1f}% | {r['false_alarm']*100:.1f}% | {r['confusion']*100:.1f}% | {r['ref_speakers']}/{r['hyp_speakers']} | {('%.3f' % r['rtf']) if r.get('rtf') is not None else '-'} |")
