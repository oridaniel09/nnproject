"""Time one pyflate variant. Usage: ablate.py <variant-file> <loops>"""
import hashlib
import importlib.machinery
import importlib.util
import os
import sys
import time

BM = ("/usr/local/lib/python3.10/dist-packages/pyperformance/"
      "data-files/benchmarks/bm_pyflate")
DATA = os.path.join(BM, "data", "interpreter.tar.bz2")

path = sys.argv[1] if os.path.isabs(sys.argv[1]) else os.path.join(BM, sys.argv[1])
loops = int(sys.argv[2]) if len(sys.argv) > 2 else 10

loader = importlib.machinery.SourceFileLoader("bmv", path)
spec = importlib.util.spec_from_file_location("bmv", path, loader=loader)
bm = importlib.util.module_from_spec(spec)
sys.modules["bmv"] = bm
spec.loader.exec_module(bm)

fp = open(DATA, "rb")
best = None
for _ in range(loops):
    fp.seek(0)
    field = bm.RBitfield(fp)
    assert field.readbits(16) == 0x425a
    t0 = time.perf_counter()
    out = bm.bzip2_main(field)
    dt = time.perf_counter() - t0
    best = dt if best is None else min(best, dt)
fp.close()

digest = hashlib.md5(out).hexdigest()
assert digest == "afa004a630fe072901b1d9628b960974", "WRONG OUTPUT " + digest
print("%-18s best=%.4fs  (md5 ok)" % (os.path.basename(path), best))
