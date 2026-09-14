# Ablation — attributing the speedup to each change

Each optimization applied on its own, so the two are attributed separately
instead of inferred from profile shares. Built by `mkvariants.py` (which
derives the single-change variants from the baseline and optimized sources)
and timed by `ablate.py`. Every variant asserts the benchmark's own output
md5, so all four rows below decompressed correctly.

Wall clock is best-of-12 for a single decompression; instructions are
`perf stat -r 3` over 3 decompressions plus interpreter startup.

| Variant | Time | vs baseline | Instructions | vs baseline |
|---|---|---|---|---|
| baseline | 1.1136 s | — | 21,676,820,021 | — |
| move_to_front only | 0.9358 s | **-16.0%** | 19,094,841,018 | **-11.9%** |
| find_next_symbol only | 0.8828 s | **-20.7%** | 16,863,774,707 | **-22.2%** |
| both | 0.7138 s | **-35.9%** | 14,364,987,673 | **-33.7%** |

## Attribution

| | Time saved | Share of baseline | Instructions saved |
|---|---|---|---|
| `find_next_symbol` | 0.2308 s | **20.7%** | 4.81 B |
| `move_to_front` | 0.1778 s | **16.0%** | 2.58 B |
| sum of the two | 0.4086 s | 36.7% | 7.40 B |
| both applied together | 0.3998 s | 35.9% | 7.31 B |

The two changes are **almost perfectly additive** — the sum of their individual
savings (0.4086 s) is within 2.2% of the measured combined saving (0.3998 s),
and within 1.1% on instruction count. They touch disjoint code, so this is
what you would expect; it is worth stating because it means neither number is
double-counting the other.

## Cross-check against the profile

The py-spy profile predicted this before the ablation was run:
`find_next_symbol` held 47.22% of baseline runtime and still holds 26.30%
after the change, so the change should be worth 47.22 - 26.30 = **20.9%**.
Measured: **20.7%**. The profile and the stopwatch agree to within 0.2 points.

## Per decoded symbol

148,271 symbols are decoded per decompression. Dividing the instruction counts
above by the 3 decompressions they cover:

| | Instructions per decompression | Per decoded symbol |
|---|---|---|
| baseline, whole benchmark | 7.23 B | ~48,732 |
| baseline, `find_next_symbol` share (47.22%) | 3.41 B | ~23,011 |
| saved by the change | 1.60 B | ~10,820 |
| `find_next_symbol` after the change | 1.81 B | ~12,191 |

The ~23,011 instructions per symbol the baseline spent inside `find_next_symbol`
matches the ~22,800 figure quoted in the presentation, which is a useful
independent check that the profile attribution was right.
