# WER with a Whisper-style basic normaliser (lowercase, strip punctuation, collapse whitespace, map common contractions apart).
import sys, re, json, unicodedata
def norm(s):
    s = s.lower()
    s = unicodedata.normalize('NFKC', s)
    s = re.sub(r"[‘’']", "'", s)
    s = re.sub(r"[^\w\s']", " ", s)   # drop punctuation, keep apostrophes
    s = re.sub(r"\s+", " ", s).strip()
    return s.split()
def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h)+1))
    for i in range(1, len(r)+1):
        prev, d[0] = d[0], i
        for j in range(1, len(h)+1):
            cur = d[j]
            d[j] = min(d[j]+1, d[j-1]+1, prev + (r[i-1] != h[j-1]))
            prev = cur
    return d[len(h)], len(r)
if __name__ == '__main__':
    ref = open(sys.argv[1]).read(); hyp = open(sys.argv[2]).read()
    e, n = wer(ref, hyp); print(f"{100*e/n:.2f}% ({e}/{n})")
