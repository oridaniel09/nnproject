#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# General Parameters
# ==========================================

# 1. The number of runs for perf stat
RUNS="${RUNS:-3}"

# Image parameters chosen before each run
IMG_WIDTH="${WIDTH:-800}"
IMG_HEIGHT="${HEIGHT:-800}"

# 2. The sampling rate of perf / py-spy
# Minimal: 1 Hz
# Maximal: System dependent (often 100000 Hz via /proc/sys/kernel/perf_event_max_sample_rate)
PYSPY_RATE="${RATE:-999}"

# Events list requested for profiling
EVENTS="cpu-clock,task-clock,cycles,instructions,branch-instructions,branch-misses,bus-cycles,cache-references,cache-misses,ref-cycles,page-faults,minor-faults,major-faults,context-switches,LLC-loads,LLC-stores"

# ==========================================
# 1. Patch & Compile
# ==========================================
echo "Patching Praytrace.py to target .so instead of .dll..."
sed -i 's/CraytraceLib\.dll/CraytraceLib\.so/g' Praytrace.py

echo "Compiling Craytrace.c into CraytraceLib.so (-O0)..."
gcc -shared -fPIC -O0 Craytrace.c -o CraytraceLib.so -lm

# ==========================================
# 2. Profiling Execution
# ==========================================
RESULTS_DIR="profile_results"
mkdir -p "$RESULTS_DIR"

for TARGET in "simpleRaytrace.py" "Praytrace.py"; do
    echo -e "\n=========================================="
    echo " Profiling: $TARGET"
    echo "=========================================="
    
    PERF_OUT="$RESULTS_DIR/${TARGET}_perf_stat.txt"
    SVG_OUT="$RESULTS_DIR/${TARGET}_flamegraph.svg"
    
    # Perf stat hardware counters
    echo "Running perf stat ($RUNS runs)..."
    perf stat -r "$RUNS" -e "$EVENTS" -o "$PERF_OUT" \
        -- python3 "$TARGET" --width="$IMG_WIDTH" --height="$IMG_HEIGHT"
    
    # Py-spy flame graph 
    echo "Generating native Flame Graph at ${PYSPY_RATE}Hz..."
    py-spy record --rate "$PYSPY_RATE" --native --output "$SVG_OUT" \
        -- python3 "$TARGET" --width="$IMG_WIDTH" --height="$IMG_HEIGHT"
    
    echo "Saved $PERF_OUT"
    echo "Saved $SVG_OUT"
done