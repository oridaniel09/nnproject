# Ablation — attributing the speedup to each change

Each optimization applied on its own, so the two are attributed separately
instead of inferred from profile shares. Built by `mkvariants.py` (which
derives the single-change variants from the baseline and optimized sources)
and timed by `ablate.py`. Every variant asserts the benchmark's own output
md5, so all four rows below decompressed correctly.

Produced by `./script_pyflate.sh --ablation` (2026-09-15); raw output in
`results/ablation.txt`. Wall clock is best-of-12 for a single decompression;
instructions are `perf stat -r 3` over 3 decompressions plus interpreter
startup.

| Variant | Time | vs baseline | Instructions | vs baseline |
|---|---|---|---|---|
| baseline | 1.1261 s | — | 21,524,503,431 | — |
| move_to_front only | 0.9491 s | **-15.7%** | 19,045,898,811 | **-11.5%** |
| find_next_symbol only | 0.8691 s | **-22.8%** | 16,979,507,191 | **-21.1%** |
| both | 0.7099 s | **-37.0%** | 14,344,547,696 | **-33.4%** |

## Attribution

| | Time saved | Share of baseline | Instructions saved |
|---|---|---|---|
| `find_next_symbol` | 0.2570 s | **22.8%** | 4.54 B |
| `move_to_front` | 0.1770 s | **15.7%** | 2.48 B |
| sum of the two | 0.4340 s | 38.5% | 7.02 B |
| both applied together | 0.4162 s | 37.0% | 7.18 B |

The two changes are **close to additive** — the sum of their individual
savings (0.4340 s) is within 4.3% of the measured combined saving (0.4162 s),
and within 2.2% on instruction count. They touch disjoint code, so this is
what you would expect; it is worth stating because it means neither number is
double-counting the other.

## Cross-check against the profile

The py-spy profile predicted this before the ablation was run:
`find_next_symbol` held 46.43% of baseline runtime and still holds 24.07%
after the change, so the change should be worth 46.43 - 24.07 = **22.4%**.
Measured: **22.8%**. The profile and the stopwatch agree to within 0.4 points.

## Per decoded symbol

148,271 symbols are decoded per decompression. Dividing the instruction counts
above by the 3 decompressions they cover:

| | Instructions per decompression | Per decoded symbol |
|---|---|---|
| baseline, whole benchmark | 7.17 B | ~48,390 |
| baseline, `find_next_symbol` share (46.43%) | 3.33 B | ~22,467 |
| saved by the change | 1.51 B | ~10,218 |
| `find_next_symbol` after the change | 1.82 B | ~12,249 |

The ~22,467 instructions per symbol the baseline spent inside `find_next_symbol`
matches the ~22,800 figure quoted in the presentation to within 1.5%, which is
a useful independent check that the profile attribution was right.
