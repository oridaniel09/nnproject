# Pyflate — software optimizations

Two changes, targeting the two hotspots identified in the baseline analysis.
Both are confined to `run_benchmark.py`; the full diff against the pristine
pyperformance source is `src/optimizations.patch`.

Baseline attribution (py-spy, cumulative share of `decode_huffman_block`):

| Frame | % of runtime |
|---|---|
| `find_next_symbol` | 47.22% |
| `move_to_front` | 15.39% |
| `bwt_reverse` | 13.50% |
| own lines | 21.58% |

The baseline analysis showed this is an instruction-count problem, not a
branch- or cache-miss problem (IPC 2.63, 0.34% branch misses). So both
optimizations attack the same thing: the number of Python bytecodes executed
per decoded symbol.

---

## 1. Huffman decoding — canonical decode table instead of a linear scan

**Where:** `HuffmanTable.build_decode_table()` (new) and the fast path in
`HuffmanTable.find_next_symbol()`.

**The problem.** The original `find_next_symbol` decodes one symbol by walking
`self.table` from the front:

```python
cached_length = -1
cached = None
for x in self.table:
    if cached_length != x.bits:
        cached = field.snoopbits(x.bits)
        cached_length = x.bits
    if (reversed and x.reverse_symbol == cached) or (not reversed and x.symbol == cached):
        field.readbits(x.bits)
        return x.code
```

Measured on the benchmark's own input (`scan_stats.py`, raw output in
`scan_stats.txt`): 148,271 symbols are decoded per decompression against a
147-entry table with code lengths 2..15. The scan walks a mean of **6.0 table
entries** per symbol (median 3, p90 14, worst case all 147), and peeks the
bitstream a mean of **2.30 times** — once per distinct code length it reaches.

So the cost per symbol is two things stacked:

1. ~6 Python loop iterations, each with two or three attribute loads on a
   `__dict__`-backed `HuffmanLength` object.
2. ~2.3 `snoopbits()` calls plus a final `readbits()` — and each of those is
   itself 2-3 Python calls, because `snoopbits()` calls `needbits()` and
   `_mask()`. That is roughly **9 Python function calls per decoded symbol**,
   and it is the larger of the two costs.

**The fix.** bzip2's Huffman codes are *canonical*:
`populate_huffman_symbols()` hands out codes in increasing `(bits, code)`
order, so the codes of any one length are consecutive integers. That makes a
length-indexed test sufficient — the shape the reference C bzip2 decoder uses:

- `limit[n]` — the largest valid code of length `n`
- `base[n]`  — offset such that `perm[v - base[n]]` is the decoded symbol
- `perm[]`   — symbols in canonical order

Decoding becomes: peek `min_bits`, and while the peeked value exceeds
`limit[n]`, take one more bit. That is a walk over *code lengths* — a measured
mean of 2.30 iterations, with 48% of symbols resolved on the very first peek —
instead of a 6.0-entry walk over the symbol table.

Worked example, using a real table from the input (lengths 2..15):

| len | codes | `limit` | `base` |
|---|---|---|---|
| 2 | 3 | 2 | 0 |
| 3 | 0 | -1 | 0 |
| 4 | 1 | 12 | 9 |
| 5 | 2 | 27 | 22 |
| ... | | | |

Peek 2 bits. If `v <= 2` the symbol is `perm[v - 0]` and we are done — that is
the 48% case. Otherwise `v == 3`; length 3 has no codes so `limit[3] == -1`
rejects everything and we take another bit. At 4 bits `v` is in 12..15, and
`v <= 12` gives `perm[12 - 9] == perm[3]`.

The bit accessors are inlined into the loop rather than called, which is where
most of the win actually comes from. The new loop peeks the same ~2.3 times per
symbol as the old one did — but as inline shift-and-mask arithmetic instead of
`snoopbits()` -> `needbits()` + `_mask()`. The profile confirms it:
`snoopbits`, `readbits` and `_mask` together fall from 25.06% of runtime to
0.65%.

The fast path is guarded by `not reversed and self.perm is not None`. The
gzip/DEFLATE path uses `reversed=True` (bit-reversed codes, which are not
canonical in this sense) and still takes the original scan, so gzip
decompression is untouched.

## 2. Move-to-front — rotate in place instead of rebuilding the list

**Where:** `move_to_front()`.

**The problem.**

```python
l[:] = l[c:c + 1] + l[0:c] + l[c + 1:]
```

Three slices, concatenated into a fourth list, copied back over `l`: four O(n)
passes and four allocations per call. The list is ~150 entries and the function
is called ~90k times per decompression.

**The fix.**

```python
if c:
    l.insert(0, l.pop(c))
```

The same rotation as two C-level `memmove`s inside a single list object, with
no intermediate objects. It also makes the `c == 0` case — the repeat case MTF
exists to make common — completely free, where the original still rebuilt the
whole list.

---

## Correctness

`verify_correctness.py` decompresses the benchmark's own input
(`interpreter.tar.bz2`) three ways — the pristine baseline implementation, the
optimized one, and `libbz2` — and requires all three to be byte-identical:

```
baseline    399360 bytes  md5=afa004a630fe072901b1d9628b960974
optimized   399360 bytes  md5=afa004a630fe072901b1d9628b960974
libbz2      399360 bytes  md5=afa004a630fe072901b1d9628b960974

all three identical: True
```

The benchmark itself also asserts this md5 at the end of every run, so no
timing result can be produced from an incorrect decompression.

## Results

See `overview/comparison.md`.
