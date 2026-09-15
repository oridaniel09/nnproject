#!/usr/bin/env bash
#
# script_pyflate.sh — reproduce every pyflate result in this repository.
#
# THIS SCRIPT RUNS ON THE QEMU VM, as root, from this directory. From the host:
#     scp -r Pyflate qemu-naranja:/root/nnproject/
#     ssh qemu-naranja 'cd /root/nnproject/Pyflate && ./script_pyflate.sh'
#     scp -r qemu-naranja:/root/nnproject/Pyflate/results Pyflate/
#
# Stages:
#   0. setup      perf, python3-dbg, python3-venv, pyperformance 1.14.0, py-spy
#   1. baseline   install src/run_benchmark.baseline.py into pyperformance, measure
#   2. optimized  install src/run_benchmark.py into pyperformance, measure,
#                 check output against the baseline and libbz2
#   3. compare    pyperformance compare + perf stat before/after table
#   4. restore    put the original benchmark back — always, even on failure
#
# Per variant, in results/<label>/:
#   correctness.txt                  output md5 check (ablate.py)
#   sanity.txt                       unprofiled speed, 3 decompressions
#   pyflate_<label>.json             pyperformance timings (release python)
#   pyflate_run_<label>.log          pyperformance console output
#   pyflate_flamegraph_<label>.svg   py-spy flame graph (Python function names)
#   pyflate_<label>.folded           py-spy raw stacks
#   pyflate_hotspots_<label>.txt     self / cumulative time per function
#   pyflate_perfstat_<label>.txt     perf stat hardware counters
#   perf_report_<label>.txt          perf record call-graph report (Project.pdf page 1)
# And in results/:
#   verify_correctness.txt           baseline == optimized == libbz2
#   compare_pyflate.txt              pyperformance compare + counter deltas
#   ablation.txt                     each optimization on its own (--ablation)
#
# Usage:
#     ./script_pyflate.sh                      # everything
#     ./script_pyflate.sh --skip-setup         # tools already installed
#     ./script_pyflate.sh --only baseline      # measure one variant
#     ./script_pyflate.sh --ablation           # also time each change separately
#
# Env overrides:
#     PYSPY_LOOPS=20      decompressions under py-spy
#     PYSPY_RATE=999      py-spy sampling rate (Hz)
#     PERFSTAT_LOOPS=5    decompressions per perf stat run
#     PERFSTAT_RUNS=3     perf stat -r repeats
#     PERFREC_LOOPS=1     decompressions under perf record (~19 MB of data each)
#     PERFREC_RATE=999    perf record sampling rate (Hz)
#     ABLATION_LOOPS=12   best-of-N decompressions per ablation variant
#     SKIP_PYPERF=1       skip the (slow) pyperformance timing runs
#     BENCH_PYTHON=...    release interpreter to benchmark (default /usr/bin/python3)
#     DBG_PYTHON=...      debug interpreter for perf record (default /usr/bin/python3-dbg)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
RESULTS="$HERE/results"
DRIVER="$HERE/pyspy_driver.py"

BENCH_PY="${BENCH_PYTHON:-/usr/bin/python3}"
DBG_PY="${DBG_PYTHON:-/usr/bin/python3-dbg}"
PYPERFORMANCE_VERSION=1.14.0

PYSPY_LOOPS="${PYSPY_LOOPS:-20}"
PYSPY_RATE="${PYSPY_RATE:-999}"
PERFSTAT_LOOPS="${PERFSTAT_LOOPS:-5}"
PERFSTAT_RUNS="${PERFSTAT_RUNS:-3}"
PERFREC_LOOPS="${PERFREC_LOOPS:-1}"
PERFREC_RATE="${PERFREC_RATE:-999}"
ABLATION_LOOPS="${ABLATION_LOOPS:-12}"

# md5 of the unmodified bm_pyflate/run_benchmark.py shipped with pyperformance 1.14.0.
BASELINE_MD5=71491b1c3bdfef2ce281a7cb4d583303
# The helper scripts (pyspy_driver.py, ablate.py, verify_correctness.py,
# mkvariants.py) hardcode this location.
EXPECTED_BM=/usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_pyflate

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

SKIP_SETUP=0
ONLY=""
ABLATION=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-setup) SKIP_SETUP=1 ;;
        --only)
            ONLY="${2:-}"; shift
            case "$ONLY" in baseline|optimized) ;; *) die "--only takes 'baseline' or 'optimized'" ;; esac ;;
        --ablation) ABLATION=1 ;;
        -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

md5()        { md5sum "$1" | cut -d' ' -f1; }
py_debug()   { "$1" -c 'import sysconfig; print(sysconfig.get_config_var("Py_DEBUG") or 0)'; }
json_python() {
    "$BENCH_PY" -c 'import json, sys; print(json.load(open(sys.argv[1]))["metadata"]["python_executable"])' "$1"
}


# ----------------------------------------------------------------------
# 0. Setup
# ----------------------------------------------------------------------
setup() {
    say "0. Setup"
    local p missing=()
    for p in linux-tools-common "linux-tools-$(uname -r)" python3-dbg python3-venv python3-pip; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        apt-get update
        apt-get install -y "${missing[@]}"
    else
        echo "apt packages already installed"
    fi

    if "$BENCH_PY" -m pip show pyperformance 2>/dev/null | grep -qx "Version: $PYPERFORMANCE_VERSION"; then
        echo "pyperformance $PYPERFORMANCE_VERSION already installed"
    else
        "$BENCH_PY" -m pip install "pyperformance==$PYPERFORMANCE_VERSION"
    fi

    if command -v py-spy >/dev/null; then
        echo "py-spy already installed"
    else
        "$BENCH_PY" -m pip install py-spy
    fi
}


# ----------------------------------------------------------------------
# Preflight: tools, interpreters, benchmark location, source files
# ----------------------------------------------------------------------
preflight() {
    say "Preflight"
    [ "$(id -u)" = 0 ] || die "run as root: the benchmark file lives under /usr/local"

    local t
    for t in perf py-spy "$BENCH_PY" "$DBG_PY"; do
        command -v "$t" >/dev/null || die "$t not found (run without --skip-setup)"
    done

    # Timings and py-spy must use a release build: the debug build runs ~2.9x
    # slower and ~30% of its samples land in debug-allocator bookkeeping.
    [ "$(py_debug "$BENCH_PY")" = 0 ] || die "$BENCH_PY is a Py_DEBUG build"
    # perf record uses the debug build on purpose: it carries the symbols and
    # DWARF unwind tables that make CPython's C call stacks readable.
    [ "$(py_debug "$DBG_PY")" = 1 ] || die "$DBG_PY is not a Py_DEBUG build"

    BM="$("$BENCH_PY" -c 'import os, pyperformance; print(os.path.join(os.path.dirname(pyperformance.__file__), "data-files", "benchmarks", "bm_pyflate"))')"
    [ -f "$BM/run_benchmark.py" ] || die "bm_pyflate not found at $BM"
    [ "$BM" = "$EXPECTED_BM" ] || die "pyperformance is at $BM, but the helper scripts expect $EXPECTED_BM"

    [ "$(md5 "$SRC/run_benchmark.baseline.py")" = "$BASELINE_MD5" ] \
        || die "src/run_benchmark.baseline.py is not the unmodified benchmark"
    if cmp -s "$SRC/run_benchmark.baseline.py" "$SRC/run_benchmark.py"; then
        die "src/run_benchmark.py is identical to the baseline"
    fi

    # verify_correctness.py and mkvariants.py read the original from here.
    cp "$SRC/run_benchmark.baseline.py" "$BM/run_benchmark.py.baseline"

    echo "benchmark dir : $BM"
    echo "release python: $BENCH_PY ($("$BENCH_PY" --version 2>&1))"
    echo "debug python  : $DBG_PY"
    echo "installed now : $(md5 "$BM/run_benchmark.py")"
}


# ----------------------------------------------------------------------
# Swapping the benchmark file pyperformance runs
# ----------------------------------------------------------------------
variant_src() {
    case "$1" in
        baseline)  echo "$SRC/run_benchmark.baseline.py" ;;
        optimized) echo "$SRC/run_benchmark.py" ;;
    esac
}

install_variant() {
    local src
    src="$(variant_src "$1")"
    cp "$src" "$BM/run_benchmark.py"
    rm -rf "$BM/__pycache__"
    cmp -s "$src" "$BM/run_benchmark.py" || die "failed to install the $1 benchmark"
    echo "installed $1 benchmark: $(md5 "$BM/run_benchmark.py")"
}

restore() {
    [ -n "${BM:-}" ] || return 0
    cp "$SRC/run_benchmark.baseline.py" "$BM/run_benchmark.py"
    rm -rf "$BM/__pycache__"
    say "4. Restored the original benchmark: $(md5 "$BM/run_benchmark.py")"
}


# ----------------------------------------------------------------------
# Measurements for one variant
# ----------------------------------------------------------------------
perf_group() {
    local title="$1" events="$2"
    echo
    echo "===== $title ====="
    echo "perf stat -r $PERFSTAT_RUNS -e $events"
    echo
    perf stat -r "$PERFSTAT_RUNS" -e "$events" \
        -- "$BENCH_PY" "$DRIVER" "$PERFSTAT_LOOPS" 2>&1 || true
}

measure() {
    local label="$1"
    local res="$RESULTS/$label"
    mkdir -p "$res"

    say "$label: install"
    install_variant "$label"

    # --- a. correctness + unprofiled speed --------------------------------
    say "$label: a. correctness and sanity check"
    # ablate.py asserts the decompressed output's md5; a wrong result stops the script.
    "$BENCH_PY" "$HERE/ablate.py" run_benchmark.py 1 | tee "$res/correctness.txt"
    "$BENCH_PY" "$DRIVER" 3 | tee "$res/sanity.txt"

    # --- b. pyperformance timings -----------------------------------------
    if [ "${SKIP_PYPERF:-0}" = 1 ]; then
        say "$label: b. pyperformance — SKIPPED (SKIP_PYPERF=1)"
    else
        say "$label: b. pyperformance run (60 samples, takes a few minutes)"
        local json="$res/pyflate_$label.json" log="$res/pyflate_run_$label.log"
        rm -f "$json"   # pyperformance refuses to overwrite an existing output file
        # Run from $HERE so both variants share one venv under ./venv, and pass
        # --python so the release interpreter is benchmarked rather than the
        # python3-dbg in the pyperformance command's shebang.
        if ! (cd "$HERE" && "$BENCH_PY" -m pyperformance run --python "$BENCH_PY" \
                --benchmarks pyflate -o "$json") > "$log" 2>&1; then
            tail -20 "$log"
            die "pyperformance run failed — see $log"
        fi
        tail -5 "$log"
        local benched
        benched="$(json_python "$json")"
        [ "$(py_debug "$benched")" = 0 ] || die "pyperformance benchmarked a Py_DEBUG build: $benched"
        echo "benchmarked: $benched"
    fi

    # --- c. py-spy flame graph ---------------------------------------------
    # py-spy reads CPython's frame objects, so stacks carry Python function
    # names; perf only sees the C interpreter underneath them.
    say "$label: c. py-spy flame graph ($PYSPY_LOOPS decompressions @ ${PYSPY_RATE} Hz)"
    local svg="$res/pyflate_flamegraph_$label.svg"
    rm -f "$svg"
    # py-spy exits non-zero after its child ends even on success; check the file instead.
    py-spy record --rate "$PYSPY_RATE" --output "$svg" \
        -- "$BENCH_PY" "$DRIVER" "$PYSPY_LOOPS" 2>&1 | tail -3 || true
    [ -s "$svg" ] || die "py-spy produced no flame graph"
    echo "wrote $svg"

    # --- d. py-spy raw stacks + hotspot tables -----------------------------
    say "$label: d. py-spy raw stacks and hotspot tables"
    local folded="$res/pyflate_$label.folded" hot="$res/pyflate_hotspots_$label.txt"
    rm -f "$folded"
    py-spy record --rate "$PYSPY_RATE" --format raw --output "$folded" \
        -- "$BENCH_PY" "$DRIVER" "$PYSPY_LOOPS" 2>&1 | tail -3 || true
    [ -s "$folded" ] || die "py-spy produced no raw stacks"
    {
        echo "# pyflate hotspots — $label"
        echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from $(basename "$folded")"
        echo
        echo "===== SELF TIME (leaf frame — where the CPU actually is) ====="
        # Each folded line is "frame;frame;... <count>".
        awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
               m=split($0,f,";"); tot+=cnt; leaf[f[m]]+=cnt }
             END { printf "TOTAL SAMPLES: %d\n\n", tot;
                   for (k in leaf) printf "%8d  %6.2f%%  %s\n", leaf[k], 100*leaf[k]/tot, k }' \
            "$folded" | sort -rn | head -25
        echo
        echo "===== CUMULATIVE (frame anywhere in the stack) ====="
        # Count each frame at most once per stack, or recursion inflates the total.
        awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
               m=split($0,f,";"); tot+=cnt; delete seen;
               for (i=1;i<=m;i++) if (!(f[i] in seen)) { cum[f[i]]+=cnt; seen[f[i]]=1 } }
             END { for (k in cum) printf "%8d  %6.2f%%  %s\n", cum[k], 100*cum[k]/tot, k }' \
            "$folded" | sort -rn | head -20
        echo
        echo "===== PER FUNCTION (all lines of a function merged) ====="
        printf "%8s  %7s  %7s  %s\n" samples cum self function
        # Frames are "func (file:line)"; dropping the line number makes each
        # function one row, still counted at most once per stack.
        awk '{ n=split($0,a," "); cnt=a[n]; sub(/ [0-9]+$/,"");
               m=split($0,f,";"); tot+=cnt; delete seen;
               for (i=1;i<=m;i++) { fn=f[i]; sub(/:[0-9]+\)$/,")",fn);
                   if (!(fn in seen)) { cum[fn]+=cnt; seen[fn]=1 } }
               leaf=f[m]; sub(/:[0-9]+\)$/,")",leaf); self[leaf]+=cnt }
             END { for (k in cum) printf "%8d  %6.2f%%  %6.2f%%  %s\n", cum[k], 100*cum[k]/tot, 100*self[k]/tot, k }' \
            "$folded" | sort -rn | head -20
    } > "$hot"
    echo "wrote $hot"

    # --- e. perf stat hardware counters ------------------------------------
    # Events go in SMALL GROUPS: this QEMU vPMU has few counters, and asking
    # for 4+ at once makes it silently report 0 instead of failing.
    say "$label: e. perf stat ($PERFSTAT_LOOPS decompressions x $PERFSTAT_RUNS runs per group)"
    local stat="$res/pyflate_perfstat_$label.txt"
    {
        echo "########################################################################"
        echo "# pyflate — hardware counter results ($label)"
        echo "########################################################################"
        echo "# interpreter : $BENCH_PY"
        echo "# benchmark   : $(md5 "$BM/run_benchmark.py") ($label)"
        echo "# workload    : $PERFSTAT_LOOPS decompression loops of interpreter.tar.bz2"
        echo "# recorded    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# cpu         : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
        echo "########################################################################"

        perf_group "GROUP 1: core + branch" "cycles,instructions,branches,branch-misses"
        perf_group "GROUP 2: last-level cache" "cache-references,cache-misses"
        perf_group "GROUP 3: L1 data cache" "L1-dcache-loads,L1-dcache-load-misses"

        echo
        echo "Counters are virtualised: good for relative before/after comparison,"
        echo "not for absolute microarchitectural claims."
    } > "$stat"
    grep -E '^ +[0-9]+ ' "$stat" || true
    echo "wrote $stat"

    # --- f. perf record call-graph report (Project.pdf page 1) -------------
    say "$label: f. perf record call graph ($PERFREC_LOOPS decompression(s), python3-dbg)"
    local report="$res/perf_report_$label.txt" tmp
    tmp="$(mktemp -d)"
    perf record -F "$PERFREC_RATE" -e cpu-clock --call-graph dwarf -o "$tmp/perf.data" \
        -- "$DBG_PY" "$DRIVER" "$PERFREC_LOOPS" 2>&1 | tail -2
    {
        echo "# pyflate — perf call-graph report ($label)"
        echo "#   perf record -F $PERFREC_RATE -e cpu-clock --call-graph dwarf -- python3-dbg pyspy_driver.py $PERFREC_LOOPS"
        echo "#   perf report --stdio --children --no-inline"
        echo "#"
        echo "# Differences from the Project.pdf page-1 command, all forced by this VM:"
        echo "#   -e cpu-clock        the virtual PMU never delivers 'cycles' samples (records 0)"
        echo "#   --call-graph dwarf  python3.10d is built without frame pointers, so -g"
        echo "#                       unwinds into garbage callers (0xfdfdfdfd..., 0xdddddddd...)"
        echo "#   --no-inline         otherwise perf report runs addr2line per address (minutes)"
        echo "#   pyspy_driver.py     profiles only the decompression, not pyperformance's"
        echo "#                       venv creation, pip installs and worker processes"
        echo "#"
        perf report -i "$tmp/perf.data" --stdio --children --no-inline 2>/dev/null
    } > "$report"
    rm -rf "$tmp"
    grep -E '^ +[0-9.]+% +[0-9.]+%' "$report" | head -8 || true
    echo "wrote $report"
}


# ----------------------------------------------------------------------
# Comparison
# ----------------------------------------------------------------------
# Before/after table from two perf stat files. Counter lines look like
# "   35794198438      instructions   # ...", with no thousands separators.
counter_table() {
    awk '
        FNR == 1 { f++ }
        $1 ~ /^[0-9]+$/ && $2 ~ /^[A-Za-z0-9-]+$/ {
            v[f, $2] = $1
            if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 }
        }
        END {
            printf "%-24s %16s %16s %9s\n", "counter", "baseline", "optimized", "change"
            for (i = 1; i <= n; i++) {
                e = order[i]; a = v[1, e]; b = v[2, e]
                if (a + 0 > 0 && b != "")
                    printf "%-24s %16s %16s %8.1f%%\n", e, a, b, 100 * (b - a) / a
                else
                    printf "%-24s %16s %16s %9s\n", e, a, b, "n/a"
            }
            if (v[1, "cycles"] > 0 && v[2, "cycles"] > 0)
                printf "%-24s %16.2f %16.2f\n", "IPC (insn/cycle)",
                    v[1, "instructions"] / v[1, "cycles"], v[2, "instructions"] / v[2, "cycles"]
        }' "$1" "$2"
}

compare() {
    say "3. Compare"
    local b="$RESULTS/baseline" o="$RESULTS/optimized"
    local bj="$b/pyflate_baseline.json" oj="$o/pyflate_optimized.json"
    local bs="$b/pyflate_perfstat_baseline.txt" os="$o/pyflate_perfstat_optimized.txt"
    {
        echo "# pyflate — baseline vs optimized"
        echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if [ -n "$ONLY" ]; then
            echo "# NOTE: run with --only $ONLY; the other variant's files are from an earlier run"
        fi
        echo
        if [ -s "$bj" ] && [ -s "$oj" ]; then
            local pb po
            pb="$(json_python "$bj")"
            po="$(json_python "$oj")"
            echo "baseline  benchmarked with: $pb"
            echo "optimized benchmarked with: $po"
            if [ "$pb" = "$po" ]; then
                echo "same interpreter and venv for both: yes"
            else
                echo "WARNING: different interpreters/venvs — re-run both to compare timings fairly"
            fi
            echo
            echo "===== pyperformance compare ====="
            "$BENCH_PY" -m pyperformance compare -O table "$bj" "$oj"
            echo
            "$BENCH_PY" -m pyperformance compare "$bj" "$oj"
        else
            echo "(pyperformance compare skipped: need both $bj and $oj)"
        fi
        echo
        echo "===== perf stat: $PERFSTAT_LOOPS decompressions x $PERFSTAT_RUNS runs ====="
        if [ -s "$bs" ] && [ -s "$os" ]; then
            counter_table "$bs" "$os"
        else
            echo "(skipped: need both $bs and $os)"
        fi
    } 2>&1 | tee "$RESULTS/compare_pyflate.txt"
}


# ----------------------------------------------------------------------
# Ablation: each optimization on its own
# ----------------------------------------------------------------------
ablation() {
    say "Ablation: each optimization on its own"
    # mkvariants.py derives the single-change variants from the installed
    # optimized file and run_benchmark.py.baseline.
    install_variant optimized
    "$BENCH_PY" "$HERE/mkvariants.py"
    local v
    {
        echo "# pyflate ablation — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# time: best of $ABLATION_LOOPS decompressions (ablate.py, output md5 asserted)"
        echo "# instructions: perf stat -r $PERFSTAT_RUNS over 3 decompressions plus interpreter startup"
        echo
        for v in run_benchmark.py.baseline v_mtf_only.py v_huff_only.py run_benchmark.py; do
            "$BENCH_PY" "$HERE/ablate.py" "$v" "$ABLATION_LOOPS"
            perf stat -r "$PERFSTAT_RUNS" -x, -e instructions \
                -- "$BENCH_PY" "$HERE/ablate.py" "$v" 3 2>&1 >/dev/null \
                | awk -F, '$3 ~ /^instructions/ { print "    instructions: " $1 }'
        done
    } | tee "$RESULTS/ablation.txt"
}


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
[ "$SKIP_SETUP" = 1 ] || setup
preflight
trap restore EXIT

if [ "$ONLY" != optimized ]; then
    measure baseline
fi

if [ "$ONLY" != baseline ]; then
    measure optimized
    say "optimized: output vs baseline and libbz2"
    "$BENCH_PY" "$HERE/verify_correctness.py" | tee "$RESULTS/verify_correctness.txt"
fi

if [ "$ABLATION" = 1 ]; then
    ablation
fi

compare

say "Done — results in $RESULTS"
