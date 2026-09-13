#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# General Parameters
# ==========================================

RUNS="${RUNS:-3}"
LOOPS="${LOOPS:-1}"
IMG_WIDTH="${WIDTH:-800}"
IMG_HEIGHT="${HEIGHT:-800}"

# Py-spy sampling rate (100Hz default to prevent QEMU lag/os error 10)
PYSPY_RATE="${RATE:-100}"

# Events list requested for profiling
EVENTS="cpu-clock,task-clock,cycles,instructions,branch-instructions,branch-misses,bus-cycles,cache-references,cache-misses,ref-cycles,page-faults,minor-faults,major-faults,context-switches,LLC-loads,LLC-stores"

RESULTS_DIR="profile_results"
mkdir -p "$RESULTS_DIR"

# ==========================================
# 1. Compile Standalone C Executable
# ==========================================
echo "Compiling BareCraytrace.c into an executable (-O0)..."
gcc -O0 BareCraytrace.c -o bare_c_raytrace -lm

# ==========================================
# 2. Profile Python Implementation
# ==========================================
echo -e "\n=========================================="
echo " Profiling: BareSimpleRaytrace.py"
echo "=========================================="
PERF_OUT_PY="$RESULTS_DIR/BareSimpleRaytrace_perf_stat.txt"
SVG_OUT_PY="$RESULTS_DIR/BareSimpleRaytrace_flamegraph.svg"

echo "Running perf stat ($RUNS runs)..."
perf stat -r "$RUNS" -e "$EVENTS" -o "$PERF_OUT_PY" \
    -- python3 BareSimpleRaytrace.py --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$LOOPS"

echo "Generating py-spy Flame Graph at ${PYSPY_RATE}Hz..."
py-spy record --rate "$PYSPY_RATE" --output "$SVG_OUT_PY" \
    -- python3 BareSimpleRaytrace.py --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$LOOPS" || true

echo "Saved $PERF_OUT_PY"
echo "Saved $SVG_OUT_PY"

# ==========================================
# 3. Profile Native C Implementation
# ==========================================
echo -e "\n=========================================="
echo " Profiling: bare_c_raytrace (Native C)"
echo "=========================================="
PERF_OUT_C="$RESULTS_DIR/BareCraytrace_perf_stat.txt"
PERF_DATA_C="$RESULTS_DIR/BareCraytrace_perf.data"

echo "Running perf stat ($RUNS runs)..."
perf stat -r "$RUNS" -e "$EVENTS" -o "$PERF_OUT_C" \
    -- ./bare_c_raytrace --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$LOOPS"

echo "Recording native C call stack (perf record)..."
# perf record generates a perf.data file which can be converted to a flamegraph later
perf record --call-graph fp -o "$PERF_DATA_C" \
    -- ./bare_c_raytrace --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$LOOPS"

echo "Saved $PERF_OUT_C"
echo "Saved $PERF_DATA_C"
echo -e "\nNote: To generate a Flame Graph for the C binary, run: perf script -i $PERF_DATA_C | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > c_flamegraph.svg"