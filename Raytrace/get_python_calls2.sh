#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="perf_py_reports"
mkdir -p "$OUT_DIR"

SCRIPTS=("simpleRaytrace.py" "Praytrace.py")

for script in "${SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
        echo "[-] Skipping $script: file not found."
        continue
    fi

    name="${script%.py}"
    data_file="$OUT_DIR/perf_${name}.data"
    report_file="$OUT_DIR/perf_report_${name}.txt"

    echo "============================================"
    echo " Profiling: $script"
    echo "============================================"

    # Replaced -g with --call-graph dwarf to bridge Python and Cython/C extensions[cite: 1]
    perf record -F 999 --call-graph dwarf -e cpu-clock -o "$data_file" -- python3-dbg "$script"

    echo "[-] Generating report: $report_file"
    # Export call-stack hierarchy to text[cite: 1]
    perf report -i "$data_file" --stdio > "$report_file"

    echo "[+] Done profiling $script."
    echo
done

echo "All profiles complete. Reports are stored in ./$OUT_DIR/"