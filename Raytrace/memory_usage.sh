#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# General Parameters
# ==========================================
IMG_WIDTH="${WIDTH:-200}"
IMG_HEIGHT="${HEIGHT:-200}"

RESULTS_DIR="memory_results"
mkdir -p "$RESULTS_DIR"

# ==========================================
# 1. Compile C Executable with Debug Symbols
# ==========================================
echo "Compiling BareCraytrace.c with -g for Valgrind..."
# -g is critical for Valgrind to report exact file names and line numbers
gcc -g -O0 BareCraytrace.c -o bare_c_raytrace -lm

# ==========================================
# 2. Memory Profiling Native C
# ==========================================
echo -e "\n=========================================="
echo " Profiling Memory: bare_c_raytrace"
echo "=========================================="
VALGRIND_OUT_C="$RESULTS_DIR/valgrind_c.txt"
TIME_OUT_C="$RESULTS_DIR/time_c.txt"

# Measure peak RAM footprint
/usr/bin/time -v -o "$TIME_OUT_C" \
    valgrind --tool=memcheck --leak-check=full --log-file="$VALGRIND_OUT_C" \
    ./bare_c_raytrace --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops=1

echo "C Memory Summary:"
grep "total heap usage" "$VALGRIND_OUT_C"
grep "Maximum resident set size" "$TIME_OUT_C"
echo "Full logs saved to $VALGRIND_OUT_C and $TIME_OUT_C"

# ==========================================
# 3. Memory Profiling Python
# ==========================================
echo -e "\n=========================================="
echo " Profiling Memory: BareSimpleRaytrace.py"
echo "=========================================="
VALGRIND_OUT_PY="$RESULTS_DIR/valgrind_py.txt"
TIME_OUT_PY="$RESULTS_DIR/time_py.txt"

echo "Running Python through Valgrind (this will take significantly longer)..."

# Measure peak RAM footprint
/usr/bin/time -v -o "$TIME_OUT_PY" \
    valgrind --tool=memcheck --leak-check=full --log-file="$VALGRIND_OUT_PY" \
    python3 BareSimpleRaytrace.py --width="$IMG_WIDTH" --height="$IMG_HEIGHT" --loops=1

echo "Python Memory Summary:"
grep "total heap usage" "$VALGRIND_OUT_PY"
grep "Maximum resident set size" "$TIME_OUT_PY"
echo "Full logs saved to $VALGRIND_OUT_PY and $TIME_OUT_PY"
