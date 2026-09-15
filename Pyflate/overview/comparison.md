# Pyflate — baseline vs optimized

Two software optimizations (see `optimizations.md`): a canonical-Huffman
decode table replacing the linear symbol scan in `find_next_symbol`, and
an in-place rotation replacing the four-slice list rebuild in
`move_to_front`. Output verified byte-identical to the baseline
implementation and to libbz2.

All numbers below come from one run of `./script_pyflate.sh --ablation` on the
QEMU VM (2026-09-15). Raw data: `results/compare_pyflate.txt`,
`results/baseline/`, `results/optimized/`.

## Wall clock — pyperformance, 60 samples each

Both variants were benchmarked with the same interpreter and venv
(`venv/cpython3.10-0a2f95361109-compat-31b33d68c68a`).

| Metric | Baseline | Optimized | Change |
|---|---|---|---|
| Mean | 1.141 s | 0.714 s | **1.60x faster** |
| Std dev | ±0.067 s | ±0.014 s | |
| Median | 1.125 s | 0.712 s | 1.58x faster |
| Min | 1.100 s | 0.698 s | |
| Max | 1.584 s | 0.788 s | |

Time saved per decompression: 427 ms (37.4%). `pyperformance compare` rates
the change as significant (t=48.58).

The baseline's larger std dev comes from a single 1.584 s sample; the next
slowest is 1.281 s. The VM has one CPU, so an occasional host-side hiccup lands
directly on a sample. The median, which ignores it, still gives 1.58x.

## Hardware counters — 5 decompressions x 3 runs

| Counter | Baseline | Optimized | Change |
|---|---|---|---|
| cycles | 13,595,107,086 | 8,815,163,489 | -35.2% |
| instructions | 35,899,254,692 | 23,821,962,019 | -33.6% |
| branches | 7,151,658,799 | 4,510,978,821 | -36.9% |
| branch-misses | 24,879,633 | 14,211,080 | -42.9% |
| cache-references | 24,956,205 | 20,504,605 | -17.8% |
| cache-misses | 1,849,367 | 1,863,201 | +0.7% |
| L1-dcache-loads | 10,875,206,264 | 7,176,067,428 | -34.0% |
| L1-dcache-load-misses | 278,024,538 | 70,306,891 | -74.7% |
| IPC | 2.64 | 2.70 | +2.3% |
| branch miss rate | 0.35% | 0.32% | |
| cache miss rate | 7.41% | 9.09% | |

The initial analysis called this an instruction-count problem rather than a
branch- or cache-miss problem. The counters confirm the fix matched the
diagnosis: instructions fell 33.6% and cycles fell in step with them (35.2%),
while the branch miss *rate* stayed essentially flat (0.35% -> 0.32%). IPC is
barely changed (2.64 -> 2.70) — the machine was never stalling, it was simply
being handed a third fewer instructions to run.

Two counters are worth a second look:

* **L1-dcache-load-misses fell 74.7%**, far more than the 34.0% drop in L1
  loads. This is the `move_to_front` change: the old version allocated four
  fresh lists per call, ~90k times per decompression, so the working set was
  constantly-churning new memory. Rotating one list in place keeps the same
  ~150 entries resident in L1.
* **The last-level cache miss *rate* rose (7.41% -> 9.09%)** even though the
  absolute miss count is flat (+0.7%). Cache references dropped 17.8% while the
  misses that remain are the same compulsory ones, so the ratio rises. This is
  not a regression — nothing got slower; the cheap hits were removed.

## Profile — py-spy, share of *baseline* runtime

Optimized shares are rescaled by the sample-count ratio (25818 vs 41431
samples for the same 20 decompressions), so both columns measure against
the same clock and the drops are real, not an artifact of a shrinking
denominator. Per-function totals are in the `PER FUNCTION` section of
`results/<label>/pyflate_hotspots_<label>.txt`.

| Function | Baseline (cum) | Optimized (cum) | Baseline (self) | Optimized (self) |
|---|---|---|---|---|
| `decode_huffman_block` | 99.06% | 61.33% | 21.05% | 20.29% |
| `find_next_symbol` | 46.43% | 24.07% | 17.16% | 18.38% |
| `move_to_front` | 16.92% | 2.17% | 16.92% | 2.17% |
| `bwt_reverse` | 13.41% | 13.59% | 5.43% | 5.73% |
| `bwt_transform` | 7.98% | 7.86% | 7.98% | 7.86% |
| `snoopbits` | 17.72% | 0.00% | 9.42% | 0.00% |
| `readbits` | 12.34% | 0.71% | 10.05% | 0.51% |
| `_mask` | 4.71% | 0.11% | 4.71% | 0.11% |
| `needbits` | 5.87% | 5.78% | 1.18% | 1.19% |
| `_more` | 4.69% | 4.59% | 2.82% | 2.86% |
| `_read` | 1.87% | 1.72% | 1.87% | 1.72% |

Reading the two targeted rows:

* `find_next_symbol` went from 46.43% of runtime to 24.07% — the linear table
  scan is gone, and what remains is the ~3-6 step walk over code lengths.
* `move_to_front` went from 16.92% to 2.17% — effectively eliminated.
* The bit accessors that `find_next_symbol` used to call (`snoopbits`,
  `readbits`, `_mask`) collapse from 24.18% of runtime (self) to 0.63%
  combined, because the fast path inlines them instead of making three Python
  calls and a `_mask()` allocation per code length tried. This is a large share
  of the total win and it is a *second-order* effect of optimization #1 — it
  does not show up if you only count the lines inside `find_next_symbol` itself.

`bwt_reverse` and `bwt_transform` hold steady against the baseline clock
(13.41% -> 13.59%, 7.98% -> 7.86%): their absolute cost was untouched. Within
the optimized profile alone they grow to 21.81% and 12.61%, simply because
they are what is left once the two hotspots are removed — and they are where a
third optimization would go.

## Call-graph report — perf record (Project.pdf page 1)

`results/<label>/perf_report_<label>.txt` holds the `perf report --stdio`
call-graph report the assignment's page 1 asks for, recorded with
`python3-dbg`. It shows CPython's C internals rather than pyflate's Python
functions: `_PyEval_EvalFrameDefault` is 23.0% self time in the baseline and
23.5% in the optimized run, with ~99% of samples under it. The
header of each report explains the flags that differ from page 1
(`-e cpu-clock`, `--call-graph dwarf`, `--no-inline`), all forced by the VM.

## Summary for the presentation

| | Baseline | Optimized |
|---|---|---|
| Time per decompression | 1.141 s | 0.714 s |
| Speedup | — | **1.60x** |
| Instructions per decompression | 7.18 B | 4.76 B |
| Instructions per output byte | ~17,980 | ~11,930 |
| `find_next_symbol` share | 46.43% | 24.07% |
| `move_to_front` share | 16.92% | 2.17% |
