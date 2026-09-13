#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# General Parameters
# ==========================================
PY_RUNS="${PY_RUNS:-10}"
C_RUNS="${C_RUNS:-50}"

# Independent loop counts for flame graph sampling
PY_RECORD_LOOPS="${PY_RECORD_LOOPS:-2}"
C_RECORD_LOOPS="${C_RECORD_LOOPS:-50}"

IMG_WIDTH="${WIDTH:-199}"
IMG_HEIGHT="${HEIGHT:-199}"
PYSPY_RATE="${RATE:-100}"
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

echo "Running perf stat ($PY_RUNS runs for averaging)..."
perf stat -r "$PY_RUNS" -e "$EVENTS" -o "$PERF_OUT_PY" \
    -- python3 BareSimpleRaytrace.py --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops=1

echo "Generating py-spy Flame Graph (Internal loops: $PY_RECORD_LOOPS)..."
py-spy record --rate "$PYSPY_RATE" --output "$SVG_OUT_PY" \
    -- python3 BareSimpleRaytrace.py --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$PY_RECORD_LOOPS" || true

# ==========================================
# 3. Profile Native C Implementation
# ==========================================
echo -e "\n=========================================="
echo " Profiling: bare_c_raytrace (Native C)"
echo "=========================================="
PERF_OUT_C="$RESULTS_DIR/BareCraytrace_perf_stat.txt"
PERF_DATA_C="$RESULTS_DIR/BareCraytrace_perf.data"

echo "Running perf stat ($C_RUNS runs for averaging)..."
perf stat -r "$C_RUNS" -e "$EVENTS" -o "$PERF_OUT_C" \
    -- ./bare_c_raytrace --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops=1

echo "Recording native C call stack (Internal loops: $C_RECORD_LOOPS)..."
perf record -e cpu-clock:u --call-graph fp -o "$PERF_DATA_C" \
    -- ./bare_c_raytrace --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops="$C_RECORD_LOOPS"
