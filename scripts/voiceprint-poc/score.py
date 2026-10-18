#!/usr/bin/env python3
"""Scores the harness output: same vs different speaker similarities within a session, across
sessions (same mic) and across mics, equal error rate, and identification accuracy when each
speaker is enrolled from 20 s of one session. Writes RESULTS tables to stdout."""
import json, glob, os, itertools, math, sys
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "out")
runs = {}
for path in sorted(glob.glob(os.path.join(OUT, "*.json"))):
    d = json.load(open(path))
    runs[(d["session"], d["mic"])] = d

def by_speaker(d):
    s = {}
    for w in d["windows"]:
        s.setdefault(w["speaker"], []).append(np.array(w["embedding"], dtype=np.float32))
    return s

def eer(scores, labels):
    """scores: similarities; labels: 1 same, 0 different. Returns (eer, threshold)."""
    s = np.array(scores); l = np.array(labels)
    best = (1.0, 0.0)
    for t in np.linspace(-1, 1, 2001):
        far = np.mean(s[l == 0] >= t) if (l == 0).any() else 0
        frr = np.mean(s[l == 1] < t) if (l == 1).any() else 0
        if abs(far - frr) < abs(best[0] - best[0]) or abs(far - frr) < 1e-9 or (far + frr) / 2 < best[0]:
            if (far + frr) / 2 < best[0]:
                best = ((far + frr) / 2, t)
    return best

def pair_scores(a, b, same_session):
    """All window pairs between speaker dicts a and b (same session excludes a window with itself)."""
    scores, labels = [], []
    for sa, ea in a.items():
        for sb, eb in b.items():
            for i, x in enumerate(ea):
                for j, y in enumerate(eb):
                    if same_session and sa == sb and i == j: continue
                    scores.append(float(x @ y)); labels.append(1 if sa == sb else 0)
    return scores, labels

def enrol(spk, seconds=20):
    """Mean of the first windows totalling about `seconds` of speech."""
    n = max(1, min(len(spk), int(round(seconds / 6))))
    v = np.mean(spk[:n], axis=0); return v / (np.linalg.norm(v) + 1e-9)

def identify(enrolled, probe, threshold):
    """Fraction of probe windows assigned to the right print at the threshold, plus false accepts."""
    names = list(enrolled); E = np.stack([enrolled[n] for n in names])
    correct = total = false_accept = 0
    for spk, ws in probe.items():
        for w in ws:
            sims = E @ w; k = int(np.argmax(sims)); total += 1
            if sims[k] >= threshold:
                if names[k] == spk: correct += 1
                else: false_accept += 1
    return correct / max(1, total), false_accept / max(1, total)

def meeting_series(session): return session[:-1]

print("## Windows and speed\n")
print("| session | mic | windows | speakers | ms per window |\n|---|---|---|---|---|")
for (s, m), d in runs.items():
    ms = [w["ms"] for w in d["windows"]]
    print(f"| {s} | {m} | {len(d['windows'])} | {len(d['speakers'])} | {np.mean(ms):.0f} |")

conds = {"within session": [], "across sessions, same mic": [], "across mics, same session": [], "across sessions and mics": []}
for (s1, m1), d1 in runs.items():
    for (s2, m2), d2 in runs.items():
        if meeting_series(s1) != meeting_series(s2): continue
        if (s1, m1) > (s2, m2): continue
        a, b = by_speaker(d1), by_speaker(d2)
        same_session = (s1, m1) == (s2, m2)
        key = ("within session" if same_session else
               "across sessions, same mic" if m1 == m2 else
               "across mics, same session" if s1 == s2 else "across sessions and mics")
        sc, lb = pair_scores(a, b, same_session)
        conds[key].append((sc, lb))

print("\n## Same versus different speaker, cosine similarity\n")
print("| condition | pairs | same: mean (p5) | different: mean (p95) | EER | threshold at EER |\n|---|---|---|---|---|---|")
thresholds = {}
for key, chunks in conds.items():
    if not chunks: continue
    sc = sum((c[0] for c in chunks), []); lb = sum((c[1] for c in chunks), [])
    s = np.array(sc); l = np.array(lb)
    e, t = eer(sc, lb); thresholds[key] = t
    print(f"| {key} | {len(sc)} | {s[l==1].mean():.3f} ({np.percentile(s[l==1],5):.3f}) | {s[l==0].mean():.3f} ({np.percentile(s[l==0],95):.3f}) | {100*e:.1f}% | {t:.3f} |")

print("\n## Identification within a session: enrol from the first 20 s, identify the second half\n")
print("| session | mic | threshold | correct | false accept |\n|---|---|---|---|---|")
split_candidates = sorted({round(t, 3) for t in thresholds.values()} | {0.5, 0.6, 0.7})
for (s1, m1), d1 in runs.items():
    spk = by_speaker(d1)
    enrolled = {k: enrol(ws) for k, ws in spk.items() if len(ws) >= 6}
    probe = {k: ws[len(ws) // 2:] for k, ws in spk.items() if len(ws) >= 6}
    for t in split_candidates:
        c, fa = identify(enrolled, probe, t)
        print(f"| {s1} | {m1} | {t:.3f} | {100*c:.1f}% | {100*fa:.1f}% |")

print("\n## Identification with averaged probes: enrol from 60 s, identify the mean of k consecutive 6 s windows (second half of the session)\n")
print("| session | mic | k windows | threshold | correct | false accept | unassigned |\n|---|---|---|---|---|---|---|")
def identify_avg(enrolled, probe, threshold, k):
    names = list(enrolled); E = np.stack([enrolled[n] for n in names])
    correct = total = fa = 0
    for spk, ws in probe.items():
        for i in range(0, max(0, len(ws) - k + 1), k):
            v = np.mean(ws[i:i+k], axis=0); v = v / (np.linalg.norm(v) + 1e-9)
            sims = E @ v; j = int(np.argmax(sims)); total += 1
            if sims[j] >= threshold:
                if names[j] == spk: correct += 1
                else: fa += 1
    return correct / max(1, total), fa / max(1, total), (total - correct - fa) / max(1, total)
for (s1, m1), d1 in runs.items():
    spk = by_speaker(d1)
    enrolled = {kk: enrol(ws, 60) for kk, ws in spk.items() if len(ws) >= 12}
    probe = {kk: ws[len(ws) // 2:] for kk, ws in spk.items() if len(ws) >= 12}
    for k in (1, 3, 5):
        for t in (0.4, 0.5, 0.6):
            c, fa, un = identify_avg(enrolled, probe, t, k)
            print(f"| {s1} | {m1} | {k} | {t:.2f} | {100*c:.1f}% | {100*fa:.1f}% | {100*un:.1f}% |")

print("\n## Across mics with averaged probes: enrol from 60 s on one mic, identify k-window means on the other\n")
print("| enrol | identify | k | threshold | correct | false accept | unassigned |\n|---|---|---|---|---|---|---|")
for (s1, m1), d1 in runs.items():
    enrolled = {kk: enrol(ws, 60) for kk, ws in by_speaker(d1).items() if len(ws) >= 12}
    for (s2, m2), d2 in runs.items():
        if s1 != s2 or m1 == m2: continue
        probe = by_speaker(d2)
        for k in (3, 5):
            for t in (0.4, 0.5, 0.6):
                c, fa, un = identify_avg(enrolled, probe, t, k)
                print(f"| {s1} {m1} | {s2} {m2} | {k} | {t:.2f} | {100*c:.1f}% | {100*fa:.1f}% | {100*un:.1f}% |")

print("\n## Identification across runs: enrol from 20 s in one session, identify 6 s windows elsewhere\n")
print("| enrol | identify | threshold | correct | false accept |\n|---|---|---|---|---|")
candidates = sorted({round(t, 3) for t in thresholds.values()} | {0.5, 0.6, 0.7})
for (s1, m1), d1 in runs.items():
    enrolled = {spk: enrol(ws) for spk, ws in by_speaker(d1).items() if len(ws) >= 3}
    for (s2, m2), d2 in runs.items():
        if (s1, m1) == (s2, m2) or meeting_series(s1) != meeting_series(s2): continue
        probe = by_speaker(d2)
        for t in candidates:
            c, fa = identify(enrolled, probe, t)
            print(f"| {s1} {m1} | {s2} {m2} | {t:.3f} | {100*c:.1f}% | {100*fa:.1f}% |")
