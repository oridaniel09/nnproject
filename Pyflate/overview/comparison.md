# Pyflate — baseline vs optimized

Two software optimizations (see `optimizations.md`): a canonical-Huffman
decode table replacing the linear symbol scan in `find_next_symbol`, and
an in-place rotation replacing the four-slice list rebuild in
`move_to_front`. Output verified byte-identical to the baseline
implementation and to libbz2.

## Wall clock — pyperformance, 60 samples each

| Metric | Baseline | Optimized | Change |
|---|---|---|---|
| Mean | 1.124 s | 0.718 s | **1.57x faster** |
| Std dev | ±0.018 s | ±0.016 s | |
| Min | 1.108 s | 0.704 s | |
| Max | 1.229 s | 0.811 s | |

Time saved per decompression: 407 ms (36.2%).

## Hardware counters — 5 decompressions x 3 runs

| Counter | Baseline | Optimized | Change |
|---|---|---|---|
| cycles | 13,637,215,142 | 8,990,756,292 | -34.1% |
| instructions | 35,794,198,438 | 24,102,947,178 | -32.7% |
| branches | 7,114,835,494 | 4,594,305,427 | -35.4% |
| branch-misses | 24,180,671 | 15,708,792 | -35.0% |
| cache-references | 25,762,049 | 21,307,515 | -17.3% |
| cache-misses | 1,876,831 | 1,873,285 | -0.2% |
| L1-dcache-loads | 10,767,384,277 | 7,135,835,920 | -33.7% |
| L1-dcache-load-misses | 271,623,206 | 69,172,177 | -74.5% |
| IPC | 2.62 | 2.68 | +2.1% |
| branch miss rate | 0.34% | 0.34% | |
| cache miss rate | 7.29% | 8.79% | |

The initial analysis called this an instruction-count problem rather than a
branch- or cache-miss problem. The counters confirm the fix matched the
diagnosis: instructions fell 32.7% and cycles fell in step with them (34.1%),
while the branch miss *rate* stayed flat at 0.34%. IPC is essentially unchanged
(2.62 -> 2.68) — the machine was never stalling, it was simply being handed a
third fewer instructions to run.

Two counters are worth a second look:

* **L1-dcache-load-misses fell 74.5%**, far more than the 33.7% drop in L1
  loads. This is the `move_to_front` change: the old version allocated four
  fresh lists per call, ~90k times per decompression, so the working set was
  constantly-churning new memory. Rotating one list in place keeps the same
  ~150 entries resident in L1.
* **The last-level cache miss *rate* rose (7.29% -> 8.79%)** even though the
  absolute miss count is flat (-0.2%). Cache references dropped 17.3% while the
  misses that remain are the same compulsory ones, so the ratio rises. This is
  not a regression — nothing got slower; the cheap hits were removed.

## Profile — py-spy, share of *baseline* runtime

Optimized shares are rescaled by the sample-count ratio (29298 vs 39534
samples for the same 20 decompressions), so both columns measure against
the same clock and the drops are real, not an artifact of a shrinking
denominator.

| Function | Baseline (cum) | Optimized (cum) | Baseline (self) | Optimized (self) |
|---|---|---|---|---|
| `decode_huffman_block` | 99.13% | 72.92% | 21.58% | 27.91% |
| `find_next_symbol` | 47.22% | 26.30% | 16.60% | 20.75% |
| `move_to_front` | 15.55% | 2.45% | 15.55% | 2.45% |
| `bwt_reverse` | 13.50% | 14.92% | 5.26% | 6.51% |
| `bwt_transform` | 8.24% | 8.41% | 8.24% | 8.41% |
| `snoopbits` | 18.28% | 0.00% | 9.64% | 0.00% |
| `readbits` | 13.08% | 0.75% | 10.67% | 0.53% |
| `_mask` | 4.75% | 0.12% | 4.75% | 0.12% |
| `needbits` | 6.30% | 5.65% | 1.10% | 1.12% |
| `_more` | 5.20% | 4.53% | 2.99% | 2.82% |
| `_read` | 2.21% | 1.72% | 2.21% | 1.72% |

Reading the two targeted rows:

* `find_next_symbol` went from 47.22% of runtime to 26.30% — the linear table
  scan is gone, and what remains is the ~3-6 step walk over code lengths.
* `move_to_front` went from 15.55% to 2.45% — effectively eliminated.
* The bit accessors that `find_next_symbol` used to call (`snoopbits`,
  `readbits`, `_mask`) collapse from 25.06% of runtime to 0.65% combined,
  because the fast path inlines them instead of making three Python calls and
  a `_mask()` allocation per code length tried. This is a large share of the
  total win and it is a *second-order* effect of optimization #1 — it does not
  show up if you only count the lines inside `find_next_symbol` itself.

`bwt_reverse` and `bwt_transform` grew as a share of the profile (13.50% ->
14.92%, 8.24% -> 8.41%) while their absolute cost was essentially untouched.
They are simply what is left once the two hotspots are removed, and they are
where a third optimization would go.

## Summary for the presentation

| | Baseline | Optimized |
|---|---|---|
| Time per decompression | 1.124 s | 0.718 s |
| Speedup | — | **1.57x** |
| Instructions per decompression | 7.16 B | 4.82 B |
| Instructions per output byte | ~17,900 | ~12,100 |
| `find_next_symbol` share | 47.22% | 26.30% |
| `move_to_front` share | 15.55% | 2.45% |
