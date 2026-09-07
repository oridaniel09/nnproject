#!/usr/bin/env bash
#
# performance-analyze.sh — full profiling sweep for the pyflate benchmark.
#
# Runs, in order:
#   1. pyperf timings            -> results/<label>/pyflate_<label>.json
#   2. py-spy flame graph        -> results/<label>/pyflate_flamegraph_<label>.svg
#   3. py-spy raw folded stacks  -> results/<label>/pyflate_<label>.folded
#      + self-time / cumulative hotspot tables
#   4. perf stat hardware counters -> results/<label>/pyflate_perfstat_<label>.txt
#
# THIS SCRIPT RUNS ON THE QEMU VM (it needs perf, py-spy and the benchmark venv).
# From the host:
#     scp Pyflate/performance-analyze.sh Pyflate/pyspy_driver.py qemu-naranja:/root/nnproject/Pyflate/
#     ssh qemu-naranja '/root/nnproject/Pyflate/performance-analyze.sh baseline'
#     scp -r qemu-naranja:/root/nnproject/Pyflate/results/baseline Pyflate/results/
#
# Usage:
#     ./performance-analyze.sh [label]        # label defaults to "baseline"
#     ./performance-analyze.sh optimized      # after applying optimisations
#
# Env overrides:
#     PERFSTAT_LOOPS=5   decompression loops per perf stat run
#     PERFSTAT_RUNS=3    perf stat -r repeats
#     PYSPY_LOOPS=20     decompression loops under py-spy
#     PYSPY_RATE=999     py-spy sampling rate (Hz)
#     SKIP_PYPERF=1      skip the (slow) pyperformance timing run
#     PYTHON=/path/...   force a specific interpreter
#
set -euo pipefail

LABEL="${1:-baseline}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="$HERE/results/$LABEL"
VENV_DIR="$HERE/venv"
DRIVER="$HERE/pyspy_driver.py"

PERFSTAT_LOOPS="${PERFSTAT_LOOPS:-5}"
PERFSTAT_RUNS="${PERFSTAT_RUNS:-3}"
PYSPY_LOOPS="${PYSPY_LOOPS:-20}"
PYSPY_RATE="${PYSPY_RATE:-999}"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }


# ----------------------------------------------------------------------
# 0. Preflight
# ----------------------------------------------------------------------
say "Preflight"

mkdir -p "$RESULTS"

# Locate a NON-DEBUG interpreter. This guard exists because profiling the
# python3.10d (Py_DEBUG=1) build silently produces a useless profile: ~30% of
# samples land in debug-allocator bookkeeping (_PyMem_DebugCheckAddress,
# read/write_size_t, out-of-line _Py_INCREF/_Py_DECREF) that does not exist in
# a release build, and the benchmark runs ~2.9x slower.
resolve_python() {
    if [ -n "${PYTHON:-}" ]; then echo "$PYTHON"; return 0; fi
    local p
    for p in "$VENV_DIR"/*/bin/python; do
        [ -x "$p" ] || continue
        if "$p" -c 'import pyperf' >/dev/null 2>&1; then echo "$p"; return 0; fi
    done
    return 1
}

PY="$(resolve_python)" || die "no venv interpreter with pyperf found under $VENV_DIR
Run 'pyperformance run --bench pyflate' once to create it, or set PYTHON=..."

assert_release() {
    local p="$1" what="$2"
    local dbg
    dbg="$("$p" -c 'import sysconfig; print(sysconfig.get_config_var("Py_DEBUG") or 0)')"
    [ "$dbg" = "0" ] || die "$what is a Py_DEBUG build ($p).
Profiling or timing it is misleading: ~30% of samples land in debug-allocator
bookkeeping that does not exist in a release build, and it runs ~2.9x slower."
}

IS_DEBUG=0
assert_release "$PY" "profiling interpreter"

# The interpreter pyperformance should BENCHMARK. This must be resolved and
# passed explicitly: /usr/local/bin/pyperformance has the shebang
# "#!/usr/bin/python3-dbg", so a bare `pyperformance run` defaults to
# sys.executable = the DEBUG interpreter and silently benchmarks that
# (3.14s vs 1.12s). Always pass --python.
BASE_PY="${BASE_PYTHON:-$("$PY" -c 'import sys; print(sys._base_executable or sys.executable)')}"
[ -x "$BASE_PY" ] || die "could not resolve a base interpreter (got '$BASE_PY')"
assert_release "$BASE_PY" "benchmark interpreter"

command -v perf   >/dev/null || die "perf not found"
command -v py-spy >/dev/null || die "py-spy not found — install with: pip3 install py-spy"

# The driver runs the benchmark's work function directly, bypassing the pyperf
# harness (which would otherwise pollute the profile with venv setup, calibration
# and worker subprocesses). Regenerate it if it went missing.
if [ ! -f "$DRIVER" ]; then
    warn "pyspy_driver.py missing — regenerating"
    cat > "$DRIVER" <<'PYEOF'
"""Standalone driver for profiling the pyflate benchmark.

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
PYEOF
fi

echo "label       : $LABEL"
echo "interpreter : $PY (Py_DEBUG=$IS_DEBUG)"
echo "results dir : $RESULTS"

# Sanity check: unprofiled speed. Should match the pyperf mean. If this drifts
# far from it, something about the environment changed.
say "Sanity check (unprofiled)"
"$PY" "$DRIVER" 3 | tee "$RESULTS/sanity.txt"


# ----------------------------------------------------------------------
# 1. pyperf timings — the authoritative before/after number
# ----------------------------------------------------------------------
if [ "${SKIP_PYPERF:-0}" = "1" ]; then
    say "1. pyperf timings — SKIPPED (SKIP_PYPERF=1)"
else
    say "1. pyperf timings (benchmarking $BASE_PY)"
    JSON="$RESULTS/pyflate_$LABEL.json"
    # Timing must come from an unprofiled run; profilers distort wall clock.
    # --python is mandatory here, see the BASE_PY comment above.
    pyperformance run --python "$BASE_PY" --bench pyflate -o "$JSON" \
        2>&1 | tee "$RESULTS/pyflate_run_$LABEL.log" | tail -5 \
        || warn "pyperformance run failed — see $RESULTS/pyflate_run_$LABEL.log"

    # Verify after the fact which interpreter actually got benchmarked;
    # pyperformance picks its own venv and will not tell you if it was a
    # debug build.
    if [ -s "$JSON" ]; then
        BENCHED="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["metadata"]["python_executable"])' "$JSON")"
        assert_release "$BENCHED" "interpreter pyperformance benchmarked"
        echo "verified: benchmarked $BENCHED (release build)"
    fi
fi


# ----------------------------------------------------------------------
# 2. py-spy flame graph (Python-level)
# ----------------------------------------------------------------------
# py-spy reads CPython's own frame objects out of process memory, so stacks
# carry real Python names. perf cannot do this: it only sees machine-code
# frames, i.e. the _PyEval_EvalFrameDefault interpreter staircase.
say "2. py-spy flame graph (${PYSPY_LOOPS} loops @ ${PYSPY_RATE}Hz)"

SVG="$RESULTS/pyflate_flamegraph_$LABEL.svg"
# py-spy exits non-zero ("No child process") after the child ends even on
# success, so don't let set -e kill us; verify the artifact instead.
py-spy record --rate "$PYSPY_RATE" --output "$SVG" \
    -- "$PY" "$DRIVER" "$PYSPY_LOOPS" 2>&1 | tail -4 || true
[ -s "$SVG" ] || die "py-spy produced no flame graph"
echo "wrote $SVG"


# ----------------------------------------------------------------------
# 3. py-spy raw folded stacks + hotspot tables
# ----------------------------------------------------------------------
say "3. py-spy raw folded stacks + hotspot tables"

FOLDED="$RESULTS/pyflate_$LABEL.folded"
py-spy record --rate "$PYSPY_RATE" --format raw --output "$FOLDED" \
    -- "$PY" "$DRIVER" "$PYSPY_LOOPS" 2>&1 | tail -3 || true
[ -s "$FOLDED" ] || die "py-spy produced no folded stacks"

HOT="$RESULTS/pyflate_hotspots_$LABEL.txt"
{
    echo "# pyflate hotspots — $LABEL"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from $(basename "$FOLDED")"
    echo
    echo "===== SELF TIME (leaf frame — where the CPU actually is) ====="
    # Each folded line is "frame;frame;... <count>".
    awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
           m=split($0,f,";"); tot+=cnt; leaf[f[m]]+=cnt }
         END { printf "TOTAL SAMPLES: %d\n\n", tot;
               for (k in leaf) printf "%8d  %6.2f%%  %s\n", leaf[k], 100*leaf[k]/tot, k }' \
        "$FOLDED" | sort -rn | head -25
    echo
    echo "===== CUMULATIVE (frame anywhere in the stack) ====="
    # Count each frame at most once per stack, or recursion inflates the total.
    awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
           m=split($0,f,";"); tot+=cnt; delete seen;
           for (i=1;i<=m;i++) if (!(f[i] in seen)) { cum[f[i]]+=cnt; seen[f[i]]=1 } }
         END { for (k in cum) printf "%8d  %6.2f%%  %s\n", cum[k], 100*cum[k]/tot, k }' \
        "$FOLDED" | sort -rn | head -20
} > "$HOT"
tail -30 "$HOT"
echo "wrote $HOT"


# ----------------------------------------------------------------------
# 4. perf stat hardware counters
# ----------------------------------------------------------------------
# Events are collected in SMALL GROUPS on purpose. This QEMU vPMU has few
# usable counters; programming 4+ events at once causes allocation conflicts
# and it silently reports 0 instead of erroring (we hit exactly this with
# L1-dcache-loads). Sanity-check any counter that reads exactly 0.
say "4. perf stat (${PERFSTAT_LOOPS} loops x ${PERFSTAT_RUNS} runs per group)"

STAT="$RESULTS/pyflate_perfstat_$LABEL.txt"

perf_group() {
    local title="$1" events="$2"
    echo
    echo "===== $title ====="
    echo "perf stat -r $PERFSTAT_RUNS -e $events"
    echo
    perf stat -r "$PERFSTAT_RUNS" -e "$events" \
        -- "$PY" "$DRIVER" "$PERFSTAT_LOOPS" 2>&1 || true
}

{
    echo "########################################################################"
    echo "# pyflate — hardware counter results ($LABEL)"
    echo "########################################################################"
    echo "# interpreter : $PY (Py_DEBUG=$IS_DEBUG)"
    echo "# workload    : $PERFSTAT_LOOPS decompression loops of interpreter.tar.bz2 (67562 bytes)"
    echo "# recorded    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# cpu         : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
    echo "########################################################################"

    perf_group "GROUP 1: core + branch" "cycles,instructions,branches,branch-misses"
    perf_group "GROUP 2: last-level cache" "cache-references,cache-misses"
    perf_group "GROUP 3: L1 data cache" "L1-dcache-loads,L1-dcache-load-misses"

    echo
    echo "===== NOT AVAILABLE ON THIS QEMU vPMU ====="
    echo "LLC-loads / LLC-load-misses         -> <not supported>"
    echo "dTLB-load-misses / iTLB-load-misses -> always 0 (not virtualised)"
    echo "stalled-cycles-frontend/backend     -> not exposed"
    echo
    echo "Counters are virtualised: good for relative before/after comparison,"
    echo "not for absolute microarchitectural claims."
} > "$STAT"
tail -40 "$STAT"
echo "wrote $STAT"


# ----------------------------------------------------------------------
say "Done — $RESULTS"
ls -la "$RESULTS"

cat <<EOF

Next:
  fetch     scp -r qemu-naranja:$RESULTS <local>/Pyflate/results/
  compare   pyperformance compare results/baseline/pyflate_baseline.json \\
                                   results/optimized/pyflate_optimized.json
EOF
