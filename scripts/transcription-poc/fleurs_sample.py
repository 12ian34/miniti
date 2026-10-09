# Stream the first N FLEURS dev clips per language straight out of the HF tar.gz without downloading the whole archive.
import sys, os, io, csv, gzip, tarfile, requests
N = int(sys.argv[2]) if len(sys.argv) > 2 else 25
langs = sys.argv[1].split(',')
base = 'https://huggingface.co/datasets/google/fleurs/resolve/main/data'
for lang in langs:
    out = f'fleurs/{lang}'; os.makedirs(out, exist_ok=True)
    if os.path.exists(f'{out}/ref.tsv') and len([f for f in os.listdir(out) if f.endswith('.wav')]) >= N:
        print(lang, 'cached'); continue
    tsv = requests.get(f'{base}/{lang}/dev.tsv', timeout=60).text
    refs = {}
    for row in csv.reader(io.StringIO(tsv), delimiter='\t', quoting=csv.QUOTE_NONE):
        if len(row) >= 3: refs[row[1]] = row[2]   # id, filename, raw transcription, normalized...
    r = requests.get(f'{base}/{lang}/audio/dev.tar.gz', stream=True, timeout=120)
    r.raise_for_status()
    got = 0
    with tarfile.open(fileobj=r.raw, mode='r|gz') as tar, open(f'{out}/ref.tsv', 'w') as rf:
        for m in tar:
            name = os.path.basename(m.name)
            if not m.isfile() or name not in refs: continue
            data = tar.extractfile(m).read()
            open(f'{out}/{name}', 'wb').write(data)
            rf.write(f'{name}\t{refs[name]}\n'); got += 1
            if got >= N: break
    r.close()
    print(lang, 'clips', got)
