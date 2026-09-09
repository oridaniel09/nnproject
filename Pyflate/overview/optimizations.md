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

`self.table` holds up to 258 `HuffmanLength` objects. Each iteration is a
Python loop step plus two or three attribute loads on a `__dict__`-backed
object, and each new code length costs a `snoopbits()` call which itself calls
`needbits()` and `_mask()`. The scan is O(number of symbols), so the *frequent*
symbols — the short codes Huffman exists to make cheap — are the only ones that
are cheap, and everything else pays a walk over the table. This is called once
per decoded symbol, ~22,800 instructions per symbol in the baseline.

**The fix.** bzip2's Huffman codes are *canonical*:
`populate_huffman_symbols()` hands out codes in increasing `(bits, code)`
order, so the codes of any one length are consecutive integers. That makes a
length-indexed test sufficient — the shape the reference C bzip2 decoder uses:

- `limit[n]` — the largest valid code of length `n`
- `base[n]`  — offset such that `perm[v - base[n]]` is the decoded symbol
- `perm[]`   — symbols in canonical order

Decoding becomes: peek `min_bits`, and while the peeked value exceeds
`limit[n]`, take one more bit. That is a walk over *code lengths* (~3-6 steps
for this data) instead of over the symbol table (up to 258 entries).

The bit accessors are inlined into the loop rather than called. `readbits()` /
`snoopbits()` would add three Python calls and a `_mask()` allocation per
length tried, which on a 3-6 iteration loop is most of the remaining cost.

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
