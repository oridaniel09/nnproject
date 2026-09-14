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

    # Record the call stack with debug symbols enabled (-g)
    # Note: Change 'python3' to 'python3-dbg' if you need the exact CPython allocator internal symbols (like _pymalloc_pool_extend) shown in your reference image.
    perf record -F "$RATE" -g -o "$PERF_DATA" \
        -- python3 "$TARGET" --width="$IMG_WIDTH" --height="$IMG_HEIGHT" $EXTRA_ARGS

    # Export the hierarchical call tree report to a text file
    perf report -i "$PERF_DATA" --stdio > "$REPORT_OUT"

    echo -e "\n=========================================="
    echo " Saved $TARGET hierarchy to $REPORT_OUT "
    echo "=========================================="

    # Print the top 35 lines to terminal to immediately replicate the image view
    head -n 35 "$REPORT_OUT"
done