"""Build single-change ablation variants from the baseline and optimized files."""
import os

BM = ("/usr/local/lib/python3.10/dist-packages/pyperformance/"
      "data-files/benchmarks/bm_pyflate")
base = open(os.path.join(BM, "run_benchmark.py.baseline")).read()
opt = open(os.path.join(BM, "run_benchmark.py")).read()

BASE_MTF = "def move_to_front(l, c):\n    l[:] = l[c:c + 1] + l[0:c] + l[c + 1:]\n"

# The optimized file's move_to_front, comment and all.
i = opt.index("def move_to_front(l, c):")
j = opt.index("def bwt_transform(L):")
OPT_MTF = opt[i:j].rstrip("\n") + "\n"

# huff_only = optimized, with move_to_front reverted to the baseline one-liner.
huff_only = opt[:i] + BASE_MTF + "\n\n" + opt[j:]

# mtf_only = baseline, with only move_to_front replaced.
assert BASE_MTF in base
mtf_only = base.replace(BASE_MTF, OPT_MTF)

for name, src in (("v_huff_only.py", huff_only), ("v_mtf_only.py", mtf_only)):
    p = os.path.join(BM, name)
    open(p, "w").write(src)
    print("wrote", p, len(src), "bytes")

# Sanity: each variant must differ from baseline in exactly the intended way.
print("huff_only has build_decode_table :", "build_decode_table" in huff_only)
print("huff_only has old MTF            :", BASE_MTF in huff_only)
print("mtf_only has build_decode_table  :", "build_decode_table" in mtf_only)
print("mtf_only has new MTF             :", "l.insert(0, l.pop(c))" in mtf_only)
