#!/usr/bin/env bash
#
# script_raytrace.sh — benchmark execution script for the Raytrace benchmark.
#
# A thin front-end over the profiling scripts in this directory, so the whole
# benchmark can be driven with one command and one set of parameters:
#
#   run_perf.sh          pyperf versions: perf stat + py-spy flame graphs
#                        (simpleRaytrace.py = pure Python, Praytrace.py = C via ctypes)
#   run_bare_perf.sh     "bare" versions without the pyperf harness, plus the
#                        standalone C executable
#   python_callstack.sh  perf record -g call-graph reports (Project.pdf page 1)
#   get_python_calls.sh  same, but under python3-dbg for Python-level symbols
#   memory_usage.sh      valgrind + /usr/bin/time peak RSS (needs valgrind)
#
# THIS SCRIPT RUNS ON THE QEMU VM (it needs perf, py-spy and gcc).
#
# Usage:
#     ./script_raytrace.sh                       # setup + default stages
#     ./script_raytrace.sh --stages profile,bare
#     ./script_raytrace.sh --skip-setup --stages memory
#     ./script_raytrace.sh --list
#
# Stages: profile, bare, callstack, pycalls, memory, all
# Default: profile,bare,callstack   (memory is opt-in: valgrind is slow)
#
# Parameters (environment variables, passed through to the scripts above):
#     WIDTH=199 HEIGHT=199     image size for every stage
#     RATE=100                 py-spy / perf sampling rate (Hz)
#     RUNS=3                   perf stat repeats (profile stage)
#     PY_RUNS=10 C_RUNS=50     perf stat repeats (bare stage)
#     PY_RECORD_LOOPS=2 C_RECORD_LOOPS=50   loops while sampling (bare stage)
#
# Results land in this directory: profile_results/, perf_stdio_results/,
# perf_py_reports/, memory_results/
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"                      # every helper script uses relative paths

STAGES_DEFAULT="profile,bare,callstack"
STAGES=""
SKIP_SETUP=0

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stages) STAGES="${2:-}"; shift ;;
        --skip-setup) SKIP_SETUP=1 ;;
        --list) echo "stages: profile bare callstack pycalls memory all"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done
STAGES="${STAGES:-$STAGES_DEFAULT}"
[ "$STAGES" = all ] && STAGES="profile,bare,callstack,pycalls,memory"

# ----------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------
if [ "$SKIP_SETUP" = 0 ]; then
    say "Setup"
    if [ "$(id -u)" = 0 ]; then
        pkgs=""
        for p in gcc python3-dbg "linux-tools-$(uname -r)" linux-tools-common time; do
            dpkg -s "$p" >/dev/null 2>&1 || pkgs="$pkgs $p"
        done
        case ",$STAGES," in
            *,memory,*) dpkg -s valgrind >/dev/null 2>&1 || pkgs="$pkgs valgrind" ;;
        esac
        if [ -n "$pkgs" ]; then
            echo "installing:$pkgs"
            apt-get update -qq && apt-get install -y $pkgs
        else
            echo "apt packages already installed"
        fi
        command -v py-spy >/dev/null || pip3 install py-spy
    else
        warn "not root — skipping package installation"
    fi
fi

# ----------------------------------------------------------------------
# Preflight
# ----------------------------------------------------------------------
say "Preflight"
for t in perf py-spy gcc python3; do
    command -v "$t" >/dev/null || die "$t not found (run without --skip-setup, as root)"
done
for f in Craytrace.c BareCraytrace.c simpleRaytrace.py Praytrace.py BareSimpleRaytrace.py; do
    [ -f "$f" ] || die "missing $f in $HERE"
done
echo "dir     : $HERE"
echo "stages  : $STAGES"
echo "image   : ${WIDTH:-199}x${HEIGHT:-199}"

run_stage() {
    local name="$1" script="$2"
    say "Stage: $name  ($script)"
    [ -x "$script" ] || chmod +x "$script"
    if ./"$script"; then
        echo "stage $name: OK"
    else
        local rc=$?
        warn "stage $name failed (exit $rc) — continuing"
        FAILED="$FAILED $name"
    fi
}

FAILED=""
IFS=',' read -r -a WANTED <<< "$STAGES"
for stage in "${WANTED[@]}"; do
    case "$stage" in
        profile)   run_stage profile   run_perf.sh ;;
        bare)      run_stage bare      run_bare_perf.sh ;;
        callstack) run_stage callstack python_callstack.sh ;;
        pycalls)   run_stage pycalls   get_python_calls.sh ;;
        memory)
            if command -v valgrind >/dev/null; then
                run_stage memory memory_usage.sh
            else
                warn "valgrind not installed — skipping the memory stage"
                warn "install it with: apt-get install -y valgrind"
            fi ;;
        "") ;;
        *) die "unknown stage: $stage (see --list)" ;;
    esac
done

say "Done"
for d in profile_results perf_stdio_results perf_py_reports memory_results; do
    [ -d "$d" ] && { echo "--- $d"; ls -la "$d" | tail -n +2; }
done
if [ -n "$FAILED" ]; then
    warn "stages that failed:$FAILED"
    exit 1
fi
