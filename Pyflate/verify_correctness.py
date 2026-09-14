"""Correctness check for the optimized pyflate.

Decompresses the benchmark's own input with (a) the untouched baseline
implementation, (b) the optimized one, and (c) libbz2, and requires all three
to be byte-identical.
"""
import bz2
import hashlib
import importlib.machinery
import importlib.util
import os
import sys

BM = ("/usr/local/lib/python3.10/dist-packages/pyperformance/"
      "data-files/benchmarks/bm_pyflate")
DATA = os.path.join(BM, "data", "interpreter.tar.bz2")


def load(name, path):
    # loader= is required: the baseline copy has no .py suffix, so
    # spec_from_file_location cannot infer one.
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


def decompress(mod):
    with open(DATA, "rb") as fp:
        field = mod.RBitfield(fp)
        magic = field.readbits(16)
        assert magic == 0x425a, hex(magic)
        return mod.bzip2_main(field)


base = decompress(load("bm_base", os.path.join(BM, "run_benchmark.py.baseline")))
opt = decompress(load("bm_opt", os.path.join(BM, "run_benchmark.py")))
ref = bz2.decompress(open(DATA, "rb").read())

for label, blob in (("baseline", base), ("optimized", opt), ("libbz2", ref)):
    print("%-10s %7d bytes  md5=%s" % (label, len(blob),
                                       hashlib.md5(blob).hexdigest()))

ok = base == opt == ref
print("\nall three identical:", ok)
sys.exit(0 if ok else 1)
