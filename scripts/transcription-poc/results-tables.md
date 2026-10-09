## AMI (English meetings, 4 speakers; reference = merged manual words incl. fillers)

| file | Deepgram batch | Deepgram live | Nemotron 1120 | Nemotron 560 | Apple | Parakeet v3 live | Parakeet v3 batch |
|---|---:|---:|---:|---:|---:|---:|---:|
| ES2004a Mix-Headset | 21.3% | 22.3% | 24.5% | 24.8% | 24.3% | 19.9% | 18.2% |
| ES2004a Array1-01 | 43.2% | 45.2% | 37.4% | 38.1% | 36.5% | 28.3% | 27.3% |
| IS1009a Mix-Headset | 24.2% | 25.1% | 28.2% | 28.0% | 27.6% | 24.6% | 21.9% |
| IS1009a Array1-01 | 26.1% | 29.1% | 32.8% | 33.4% | 31.5% | 24.0% | 24.9% |

### Speed and memory on AMI (M5 Pro)

| system | mean RTF | mean chunk ms | p95 chunk ms |
|---|---:|---:|---:|
| Nemotron 1120 | 0.014 | 15 | 47 |
| Nemotron 560 | 0.021 | 12 | 38 |
| Apple | 0.007 | – | – |
| Parakeet v3 live | 0.006 | – | – |
| Parakeet v3 batch | 0.006 | – | – |

### Filler words kept (count of um/uh/hmm in output vs reference)

| file | reference | Deepgram live | Nemotron 1120 | Apple | Parakeet |
|---|---:|---:|---:|---:|---:|
| ES2004a Mix-Headset | 131 | 0 | 16 | 5 | 55 |
| ES2004a Array1-01 | 131 | 0 | 10 | 8 | 45 |
| IS1009a Mix-Headset | 123 | 8 | 32 | 19 | 93 |
| IS1009a Array1-01 | 123 | 3 | 22 | 19 | 81 |

## FLEURS dev clips (25 read-speech clips per language, ~10 s each)

| language | Nemotron 1120 | Apple | Parakeet v3 | Nemotron RTF | Apple RTF |
|---|---:|---:|---:|---:|---:|
| en_us | 7.6% | 6.0% | 3.6% | 0.013 | 0.015 |
| es_419 | 5.0% | 4.1% | 11.2% | 0.015 | 0.012 |
| fr_fr | 9.9% | 5.9% | 4.3% | 0.015 | 0.013 |
| de_de | 9.7% | 5.3% | 8.5% | 0.014 | 0.012 |
| nl_nl | 14.2% | – | 8.7% | 0.020 | – |
| ru_ru | 13.2% | – | 7.7% | 0.019 | – |
| pl_pl | 19.1% | – | 6.1% | 0.022 | – |
| sv_se | 23.0% | – | 16.3% | 0.021 | – |
| el_gr | 42.4% | – | 34.1% | 0.023 | – |
