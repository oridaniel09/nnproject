# HW/SW Project — Benchmark Optimization, Analysis and Hardware Acceleration

Course project for ECE882. We picked two benchmarks from the pyperformance suite,
profiled them, optimized them, and proposed a hardware accelerator for one of them.

| Benchmark | Owner | Result |
|---|---|---|
| Pyflate — pure-Python bzip2 decompression | Ori Daniel | 1.141 s → 0.714 s, **1.60x faster** |
| Raytrace — ray tracer | Or Sasson | Python implementation replaced by a C library called through ctypes |

The hardware accelerator is built for Raytrace and lives in `Raytrace/HardAccel/SVCode/`.

## Repository layout

```
.
├── run_benchmarks.sh        one entry point for both benchmarks
├── Project.pdf              the assignment
├── prompts.md               prompts used with AI tools (Pyflate side)
├── FinalPresentation.pptx   the presentation
│
├── Pyflate/
│   ├── report_pyflate.pdf   the benchmark report
│   ├── script_pyflate.sh    baseline vs optimized: setup, run, profile, compare
│   ├── src/
│   │   ├── run_benchmark.py            the optimized benchmark
│   │   ├── run_benchmark.baseline.py   the original, for comparison
│   │   └── optimizations.patch         the diff between them
│   ├── results/             every measurement quoted in the report
│   ├── overview/            working notes from the analysis
│   ├── hardware/            accelerator sketch, presented in the slides only
│   ├── ablate.py            times each optimization on its own
│   ├── mkvariants.py        builds the one-optimization-at-a-time variants
│   ├── pyspy_driver.py      runs just the decompression, for profiling
│   ├── scan_stats.py        counts table entries walked per symbol
│   └── verify_correctness.py   checks output against the original and libbz2
│
└── Raytrace/
    ├── README.md            detailed description of this directory
    ├── script_raytrace.sh   runs all the Raytrace profiling scripts
    ├── simpleRaytrace.py    the original benchmark
    ├── Praytrace.py         the optimized version, calls into C
    ├── Craytrace.c          the C implementation
    ├── HardAccel/SVCode/    the hardware accelerator (SystemVerilog + Quartus)
    ├── profile_results/     perf stat output and flame graphs
    ├── perf_py_reports/     Python call-stack reports
    └── memory_results/      valgrind and timing output
```

## Running the benchmarks

Everything runs on the course QEMU virtual machine, as root. `perf`, `py-spy`,
`gcc` and `pyperformance` all need to be available there.

Copy the repository over and run both benchmarks:

```
scp -r nnproject qemu-naranja:/root/
ssh qemu-naranja '/root/nnproject/run_benchmarks.sh --bench both'
```

Or one at a time:

```
./run_benchmarks.sh --bench pyflate
./run_benchmarks.sh --bench raytrace
./run_benchmarks.sh --list
```

Anything after the benchmark name is passed through to that benchmark's own
script, so `./run_benchmarks.sh --bench raytrace --stages profile` works.

### Pyflate

`Pyflate/script_pyflate.sh` does the whole measurement in one go: installs what
it needs, runs pyperformance on the baseline, swaps in the optimized version,
runs it again, and writes the comparison. It restores the original benchmark
file on exit, even if it fails partway.

```
./Pyflate/script_pyflate.sh                  # full run
./Pyflate/script_pyflate.sh --skip-setup     # skip package installation
./Pyflate/script_pyflate.sh --ablation       # also time each optimization alone
```

Parameters are environment variables: `PYSPY_LOOPS`, `PYSPY_RATE`,
`PERFSTAT_LOOPS`, `PERFSTAT_RUNS`, `ABLATION_LOOPS`, `SKIP_PYPERF`.

Output goes to `Pyflate/results/`:

| File | Contents |
|---|---|
| `compare_pyflate.txt` | pyperformance comparison and the hardware counters |
| `ablation.txt` | timing of each optimization measured separately |
| `verify_correctness.txt` | md5 agreement with the original and with libbz2 |
| `baseline/`, `optimized/` | flame graph, hotspots, perf stat, perf call-graph report |

To check correctness on its own:

```
python3 Pyflate/verify_correctness.py
```

### Raytrace

```
./Raytrace/script_raytrace.sh                      # setup + default stages
./Raytrace/script_raytrace.sh --stages profile,bare
./Raytrace/script_raytrace.sh --list
```

Stages are `profile`, `bare`, `callstack`, `pycalls` and `memory`. Image size and
sampling rate are set with `WIDTH`, `HEIGHT`, `RATE`, `RUNS`. See
`Raytrace/README.md` for what each script produces.

## Reports

- `Pyflate/report_pyflate.pdf` — benchmark overview, profiling, both
  optimizations, and the measured comparison.
- The Raytrace report and the hardware accelerator proposal are submitted with
  the Raytrace material.

## Notes

- The measurements in the Pyflate report were taken on the QEMU VM: Intel Xeon
  E5-2630 v3, one logical CPU, Linux 5.15, Python 3.10.12, pyperformance 1.14.0.
- Three `perf record` flags differ from the ones in the assignment
  (`-e cpu-clock`, `--call-graph dwarf`, `--no-inline`). The VM forces each one,
  and the reason is written at the top of every `perf_report_*.txt`.
