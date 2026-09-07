"""Standalone driver for profiling the pyflate benchmark with py-spy.

Imports the unmodified pyperformance bm_pyflate benchmark and runs its
decompression workload directly, bypassing the pyperf harness so the
profile contains only pyflate frames.
"""
import os
import sys

BM_DIR = ("/usr/local/lib/python3.10/dist-packages/pyperformance/"
          "data-files/benchmarks/bm_pyflate")
sys.path.insert(0, BM_DIR)

import run_benchmark as bm  # noqa: E402

LOOPS = int(sys.argv[1]) if len(sys.argv) > 1 else 20

filename = os.path.join(BM_DIR, "data", "interpreter.tar.bz2")
dt = bm.bench_pyflake(LOOPS, filename)
print("loops=%d total=%.3fs per-loop=%.3fs" % (LOOPS, dt, dt / LOOPS))
