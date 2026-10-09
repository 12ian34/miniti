# Build a time-ordered reference transcript per AMI meeting from the manual word XML (all 4 speakers merged by start time).
import re, sys, glob, xml.etree.ElementTree as ET
for m in ['ES2004a', 'IS1009a']:
    words = []
    for f in glob.glob(f'ami/words/{m}.*.words.xml'):
        for w in ET.parse(f).getroot():
            if w.tag.endswith('}w') or w.tag == 'w':
                if w.get('punc') == 'true' or not w.text: continue
                st = w.get('starttime'); 
                if st is None: continue
                words.append((float(st), w.text.strip()))
    words.sort()
    open(f'ami/{m}.ref.txt', 'w').write(' '.join(t for _, t in words) + '\n')
    print(m, len(words), 'words; fillers um/uh:', sum(1 for _, t in words if t.lower().strip(",.") in ('um','uh','hmm','mm','mm-hmm','uh-huh')))
