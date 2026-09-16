#!/usr/bin/env bash
#
# run_benchmarks.sh — one entry point for both benchmarks in this project.
#
# Delegates to each benchmark's own script, which are the per-benchmark
# deliverables the assignment asks for:
#
#     Pyflate/script_pyflate.sh     baseline vs optimized, profiling, comparison
#     Raytrace/script_raytrace.sh   perf stat, flame graphs, call graphs, memory
#
# THIS SCRIPT RUNS ON THE QEMU VM, as root (perf, py-spy, gcc, pyperformance).
# From the host:
#     scp -r <repo> qemu-naranja:/root/nnproject/
#     ssh qemu-naranja '/root/nnproject/run_benchmarks.sh --bench both'
#     scp -r qemu-naranja:/root/nnproject/{Pyflate/results,Raytrace} ./
#
# Usage:
#     ./run_benchmarks.sh --bench pyflate  [pyflate options...]
#     ./run_benchmarks.sh --bench raytrace [raytrace options...]
#     ./run_benchmarks.sh --bench both     # both, with their defaults
#     ./run_benchmarks.sh --list
#
# Anything after the benchmark name is passed straight through, so:
#     ./run_benchmarks.sh --bench pyflate --skip-setup --ablation
#     ./run_benchmarks.sh --bench raytrace --stages profile,memory
#
# Parameters are environment variables, forwarded to whichever script runs:
#
#   pyflate   PYSPY_LOOPS=20 PYSPY_RATE=999 PERFSTAT_LOOPS=5 PERFSTAT_RUNS=3
#             PERFREC_LOOPS=1 PERFREC_RATE=999 ABLATION_LOOPS=12 SKIP_PYPERF=1
#             BENCH_PYTHON=... DBG_PYTHON=...
#   raytrace  WIDTH=199 HEIGHT=199 RATE=100 RUNS=3 PY_RUNS=10 C_RUNS=50
#             PY_RECORD_LOOPS=2 C_RECORD_LOOPS=50
#
# Examples:
#     WIDTH=64 HEIGHT=64 ./run_benchmarks.sh --bench raytrace --stages profile
#     SKIP_PYPERF=1 ./run_benchmarks.sh --bench pyflate --skip-setup
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYFLATE="$HERE/Pyflate/script_pyflate.sh"
RAYTRACE="$HERE/Raytrace/script_raytrace.sh"

say()  { printf '\n\033[1m\033[4m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

BENCH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --bench|-b)
            BENCH="${2:-}"; shift 2
            case "$BENCH" in
                pyflate|raytrace|both) ;;
                *) die "--bench takes pyflate, raytrace or both" ;;
            esac
            break ;;                       # the rest belongs to the sub-script
        --list)
            echo "benchmarks: pyflate raytrace both"
            echo "  pyflate  -> $PYFLATE"
            echo "  raytrace -> $RAYTRACE"
            exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done
[ -n "$BENCH" ] || { usage; exit 1; }
PASSTHRU=("$@")

[ "$(id -u)" = 0 ] || warn "not running as root — package installation and some
         profiling will fail; on the QEMU VM log in as root"

run_one() {
    local name="$1" script="$2"; shift 2
    [ -f "$script" ] || die "$script not found"
    [ -x "$script" ] || chmod +x "$script"
    say "BENCHMARK: $name"
    echo "running: $script ${*:-(no extra options)}"
    local start rc
    start=$(date +%s)
    "$script" "$@"
    rc=$?
    local mins=$(( ($(date +%s) - start) / 60 ))
    if [ $rc -eq 0 ]; then
        echo "[$name] finished OK in ~${mins} min"
    else
        warn "[$name] exited with status $rc after ~${mins} min"
    fi
    return $rc
}

STATUS=0
case "$BENCH" in
    pyflate)  run_one pyflate  "$PYFLATE"  "${PASSTHRU[@]+"${PASSTHRU[@]}"}" || STATUS=1 ;;
    raytrace) run_one raytrace "$RAYTRACE" "${PASSTHRU[@]+"${PASSTHRU[@]}"}" || STATUS=1 ;;
    both)
        [ ${#PASSTHRU[@]} -eq 0 ] || warn "extra options are ignored with --bench both"
        run_one pyflate  "$PYFLATE"  || STATUS=1
        run_one raytrace "$RAYTRACE" || STATUS=1 ;;
esac

say "SUMMARY"
[ "$BENCH" = raytrace ] || echo "pyflate results : $HERE/Pyflate/results/"
[ "$BENCH" = pyflate ]  || echo "raytrace results: $HERE/Raytrace/{profile_results,perf_stdio_results,perf_py_reports,memory_results}/"
[ $STATUS -eq 0 ] && echo "all requested benchmarks completed" || warn "one or more benchmarks reported an error"
exit $STATUS
