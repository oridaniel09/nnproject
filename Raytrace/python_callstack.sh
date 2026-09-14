#!/usr/bin/env bash
set -euo pipefail

IMG_WIDTH="${WIDTH:-800}"
IMG_HEIGHT="${HEIGHT:-800}"
RATE="${RATE:-999}"

RESULTS_DIR="perf_stdio_results"
mkdir -p "$RESULTS_DIR"

for TARGET in "BareSimpleRaytrace.py" "simpleRaytrace.py"; do
    BASENAME="${TARGET%.*}"
    PERF_DATA="$RESULTS_DIR/${BASENAME}_perf.data"
    REPORT_OUT="$RESULTS_DIR/${BASENAME}_report.txt"

    EXTRA_ARGS=""
    if [[ "$TARGET" == "BareSimpleRaytrace.py" ]]; then
        EXTRA_ARGS="--loops=2"
    fi

    echo -e "\n=========================================="
    echo " Recording: $TARGET"
    echo "=========================================="

    # -e cpu-clock:u uses software timer interrupts and restricts to user space
    perf record -e cpu-clock:u -F "$RATE" -g -o "$PERF_DATA" \
        -- python3 "$TARGET" --width="$IMG_WIDTH" --height="$IMG_HEIGHT" $EXTRA_ARGS

    # Export hierarchical call tree matching standard stdio view
    perf report -i "$PERF_DATA" --stdio > "$REPORT_OUT"

    echo "Saved $TARGET hierarchy to $REPORT_OUT"
    head -n 40 "$REPORT_OUT"
done