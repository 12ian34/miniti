import json, glob, os, sys
from score import wer, norm
S=os.environ.get('POC_DIR', os.path.dirname(os.path.abspath(__file__)))
def load(p):
    try: return json.load(open(p))
    except Exception: return None
print("## AMI (English meetings, 4 speakers; reference = merged manual words incl. fillers)\n")
print("| file | Deepgram batch | Deepgram live | Nemotron 1120 | Nemotron 560 | Apple | Parakeet v3 live | Parakeet v3 batch |")
print("|---|---:|---:|---:|---:|---:|---:|---:|")
def hyp(rows, f):
    if not rows: return None
    for r in rows:
        if r['file'].endswith(f) and not r.get('error'): return r
    return None
systems=[('nemotron-ami-1120','Nemotron 1120'),('nemotron-ami-560','Nemotron 560'),('apple-ami','Apple'),('parakeetlive-ami','Parakeet v3 live'),('parakeet-ami','Parakeet v3 batch')]
loaded={k:load(f'{S}/out/{k}.json') for k,_ in systems}
for m in ['ES2004a','IS1009a']:
    for ch in ['Mix-Headset','Array1-01']:
        ref=open(f'{S}/ami/{m}.ref.txt').read()
        cells=[]
        for sysn in ['batch','live']:
            e,n=wer(ref, open(f'{S}/ami/deepgram-{sysn}-{m}.{ch}.txt').read()); cells.append(f"{100*e/n:.1f}%")
        for k,_ in systems:
            r=hyp(loaded[k], f'{m}.{ch}.16k.wav')
            if r: e,n=wer(ref,r['text']); cells.append(f"{100*e/n:.1f}%")
            else: cells.append('–')
        print(f"| {m} {ch} | "+" | ".join(cells)+" |")
print("\n### Speed and memory on AMI (M5 Pro)\n")
print("| system | mean RTF | mean chunk ms | p95 chunk ms |")
print("|---|---:|---:|---:|")
for k,name in systems:
    rows=[r for r in (loaded[k] or []) if not r.get('error')]
    if not rows: continue
    rtf=sum(r['rtf'] for r in rows)/len(rows)
    cm=[r['meanChunkMs'] for r in rows if r.get('meanChunkMs')]; p9=[r['p95ChunkMs'] for r in rows if r.get('p95ChunkMs')]
    if 'live' in k or 'nemotron' not in k: cm=[]
    print(f"| {name} | {rtf:.3f} | {sum(cm)/len(cm):.0f} | {max(p9):.0f} |" if cm else f"| {name} | {rtf:.3f} | – | – |")
# fillers
print("\n### Filler words kept (count of um/uh/hmm in output vs reference)\n")
FILL={'um','uh','hmm','mm','mhm','erm','er'}
def fc(t): return sum(1 for w in norm(t) if w in FILL)
print("| file | reference | Deepgram live | Nemotron 1120 | Apple | Parakeet |")
print("|---|---:|---:|---:|---:|---:|")
for m in ['ES2004a','IS1009a']:
    for ch in ['Mix-Headset','Array1-01']:
        ref=open(f'{S}/ami/{m}.ref.txt').read(); dl=open(f'{S}/ami/deepgram-live-{m}.{ch}.txt').read()
        c=[fc(ref), fc(dl)]
        for k in ['nemotron-ami-1120','apple-ami','parakeet-ami']:
            r=hyp(loaded[k], f'{m}.{ch}.16k.wav'); c.append(fc(r['text']) if r else '–')
        print(f"| {m} {ch} | "+" | ".join(str(x) for x in c)+" |")
print("\n## FLEURS dev clips (25 read-speech clips per language, ~10 s each)\n")
print("| language | Nemotron 1120 | Apple | Parakeet v3 | Nemotron RTF | Apple RTF |")
print("|---|---:|---:|---:|---:|---:|")
for L in ['en_us','es_419','fr_fr','de_de','nl_nl','ru_ru','pl_pl','sv_se','el_gr']:
    refp=f'{S}/fleurs/{L}/ref.tsv'
    if not os.path.exists(refp): continue
    refs=dict(l.rstrip('\n').split('\t',1) for l in open(refp))
    cells=[]; rtfs=[]
    for k in ['nemotron-fleurs','apple-fleurs','parakeet-fleurs']:
        rows=load(f'{S}/out/{k}-{L}.json')
        if not rows: cells.append('–'); rtfs.append('–'); continue
        E=N=0; rt=[]
        for r in rows:
            if r.get('error'): continue
            e,n=wer(refs[os.path.basename(r['file'])], r['text']); E+=e; N+=n; rt.append(r['rtf'])
        cells.append(f"{100*E/N:.1f}%" if N else 'err'); rtfs.append(f"{sum(rt)/len(rt):.3f}" if rt else '–')
    print(f"| {L} | {cells[0]} | {cells[1]} | {cells[2]} | {rtfs[0]} | {rtfs[1]} |")
