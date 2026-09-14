#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Parameters
# ==========================================
IMG_WIDTH="${WIDTH:-800}"
IMG_HEIGHT="${HEIGHT:-800}"
PYSPY_RATE="${RATE:-100}"

RESULTS_DIR="callstack_results"
mkdir -p "$RESULTS_DIR"

# ==========================================
# Generate and Process Stacks
# ==========================================
for TARGET in "BareSimpleRaytrace.py" "simpleRaytrace.py"; do
    echo -e "\n=========================================="
    echo " Profiling Callstack: $TARGET"
    echo "=========================================="

    # Strip the .py extension for cleaner filenames
    BASENAME="${TARGET%.*}"
    FOLDED="$RESULTS_DIR/${BASENAME}.folded"
    HOT="$RESULTS_DIR/${BASENAME}_hotspots.txt"

    echo "Generating raw folded stacks with py-spy..."

    # Optional loops argument specifically for the bare implementation
    EXTRA_ARGS=""
    if [[ "$TARGET" == "BareSimpleRaytrace.py" ]]; then
        EXTRA_ARGS="--loops=2"
    fi

    py-spy record --rate "$PYSPY_RATE" --format raw --output "$FOLDED" \
        -- python3 "$TARGET" --width="$IMG_WIDTH" --height="$IMG_HEIGHT" $EXTRA_ARGS || true

    if [ ! -s "$FOLDED" ]; then
        echo "Error: py-spy produced no folded stacks for $TARGET." >&2
        continue
    fi

    echo "Processing hotspot tables..."
    {
        echo "# $TARGET hotspots"
        echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from $(basename "$FOLDED")"
        echo
        echo "===== SELF TIME (leaf frame — where the CPU actually is) ====="
        awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
               m=split($0,f,";"); tot+=cnt; leaf[f[m]]+=cnt }
             END { printf "TOTAL SAMPLES: %d\n\n", tot;
                   for (k in leaf) printf "%8d  %6.2f%%  %s\n", leaf[k], 100*leaf[k]/tot, k }' \
            "$FOLDED" | sort -rn | head -25[cite: 7]
        echo
        echo "===== CUMULATIVE (frame anywhere in the stack) ====="
        awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
               m=split($0,f,";"); tot+=cnt; delete seen;
               for (i=1;i<=m;i++) if (!(f[i] in seen)) { cum[f[i]]+=cnt; seen[f[i]]=1 } }
             END { for (k in cum) printf "%8d  %6.2f%%  %s\n", cum[k], 100*cum[k]/tot, k }' \
            "$FOLDED" | sort -rn | head -20[cite: 7]
    } > "$HOT"

    # Output results to terminal
    cat "$HOT"
    echo -e "\nSaved full tables for $TARGET to $HOT"
done