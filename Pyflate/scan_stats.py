"""Quantify the find_next_symbol change on the real benchmark input.

Instruments the BASELINE decoder to record, per decoded symbol:
  - how many table entries the linear scan walked
  - how many distinct code lengths it snooped (== steps the new path takes)
and dumps the canonical limit/base/perm tables for one real Huffman group.
"""
import collections
import importlib.machinery
import importlib.util
import os
import sys

BM = ("/usr/local/lib/python3.10/dist-packages/pyperformance/"
      "data-files/benchmarks/bm_pyflate")
DATA = os.path.join(BM, "data", "interpreter.tar.bz2")

loader = importlib.machinery.SourceFileLoader(
    "bm", os.path.join(BM, "run_benchmark.py.baseline"))
spec = importlib.util.spec_from_file_location("bm", loader.path, loader=loader)
bm = importlib.util.module_from_spec(spec)
sys.modules["bm"] = bm
spec.loader.exec_module(bm)

entries = []          # table entries scanned per symbol
lengths = []          # distinct code lengths tried per symbol
table_sizes = []
sample = {}

orig = bm.HuffmanTable.find_next_symbol


def instrumented(self, field, reversed=True):
    cached_length = -1
    cached = None
    n_entries = 0
    n_lengths = 0
    for x in self.table:
        n_entries += 1
        if cached_length != x.bits:
            cached = field.snoopbits(x.bits)
            cached_length = x.bits
            n_lengths += 1
        if ((reversed and x.reverse_symbol == cached)
                or (not reversed and x.symbol == cached)):
            field.readbits(x.bits)
            entries.append(n_entries)
            lengths.append(n_lengths)
            table_sizes.append(len(self.table))
            if not sample and len(self.table) > 50:
                sample["t"] = self
            return x.code
    raise Exception("unfound symbol")


bm.HuffmanTable.find_next_symbol = instrumented

with open(DATA, "rb") as fp:
    field = bm.RBitfield(fp)
    assert field.readbits(16) == 0x425a
    bm.bzip2_main(field)

n = len(entries)
print("decoded symbols                : %d" % n)
print("mean table size                : %.1f entries" % (sum(table_sizes) / n))
print("max table size                 : %d entries" % max(table_sizes))
print()
print("BASELINE  table entries scanned per symbol:")
print("  mean %.1f   median %d   p90 %d   max %d"
      % (sum(entries) / n, sorted(entries)[n // 2],
         sorted(entries)[int(n * .9)], max(entries)))
print()
print("OPTIMIZED code lengths tried per symbol (== loop iterations):")
print("  mean %.2f   median %d   p90 %d   max %d"
      % (sum(lengths) / n, sorted(lengths)[n // 2],
         sorted(lengths)[int(n * .9)], max(lengths)))
print()
print("  ratio (entries walked / lengths tried) = %.1fx"
      % ((sum(entries) / n) / (sum(lengths) / n)))
print()
hist = collections.Counter(lengths)
print("distribution of lengths tried:")
for k in sorted(hist):
    print("  %2d steps : %6d symbols (%5.2f%%)" % (k, hist[k], 100 * hist[k] / n))

t = sample["t"]
print()
print("=== one real Huffman group: %d symbols, code lengths %d..%d ==="
      % (len(t.table), t.min_bits, t.max_bits))
limit = [-1] * (t.max_bits + 1)
base = [0] * (t.max_bits + 1)
for index, x in enumerate(t.table):
    if limit[x.bits] < 0:
        base[x.bits] = x.symbol - index
    limit[x.bits] = x.symbol
print("len : count : limit[len] : base[len]")
cnt = collections.Counter(x.bits for x in t.table)
for b in range(t.min_bits, t.max_bits + 1):
    print("%3d : %5d : %10d : %9d" % (b, cnt.get(b, 0), limit[b], base[b]))
