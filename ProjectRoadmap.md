1. Environment setup
    Copy the Ubuntu image from naranja10 via scp and launch it in QEMU (Steps 0–1 of the guide).
    Inside the VM, set up a Python virtual environment and install pyperformance (and python3-dbg for debug symbols, needed later for perf).
    Verify perf is installed and working.

2. Choose your 2 benchmarks

    Pick 2 from the approved list of 13 (Raytrace, Deepcopy, Mdp, Pathlib, pickle/pickle_dict, Pyflate, unpack_sequence, tornado_http, sqlite_synth, Nbody, Btree, deepblue, go).
    Skim the pyperformance benchmark docs for each candidate to judge which look interesting/tractable before locking in.
3. Understand pyperformance itself

    Learn how to run a single benchmark (pyperformance run --bench <name>), how results/timings are reported, and how to compare two result files (pyperformance compare).
4. Benchmark analysis (per benchmark)

    Locate and read the benchmark's actual source in the pyperformance package.
    Identify what it does, which stdlib/third-party libraries it uses, and what data structures/algorithms drive its cost.
    If it wraps a third-party library (e.g. numpy, a crypto lib), dig into that library's relevant internals too.
5. Profile with perf and generate flame graphs

    Run each benchmark under perf record -F 999 -g with the debug build of Python.
    Generate perf_report.txt and build a flame graph from the recorded data.
Do this for both benchmarks before any changes (baseline).
6. Detect bottlenecks

    Read the flame graphs/perf reports to find hotspots — slow functions, excessive allocation, inefficient loops, etc.
7. Optimize

    For each benchmark, implement at least one concrete optimization (better algorithm, faster library, data-structure swap, refactor).
    Aim for ≥7% improvement on at least two benchmarks (stated as "sufficient").
8. Re-measure and compare

    Re-run pyperformance (and perf/flame graphs) on the optimized code.
    Produce before/after comparison data (timings, and ideally updated flame graphs showing the hotspot shrink).
9. Propose hardware acceleration

    Pick 1–2 hotspot components (one per benchmark, or two total) as accelerator targets.
    Design and implement the accelerator in Verilog/SystemVerilog/PyXHDL, including:
    inputs/outputs, data widths, interfaces, target clock frequency
    internal datapath + control logic
    HW/SW interface (driver, memory-mapped registers, DMA, etc.)
    justification for why this is a good acceleration target + expected speedup
    block diagram
    performance/area/power trade-off discussion
10. Write up the reports

    One report_<benchmark>.txt per benchmark: overview, initial analysis (flame graphs/profiling), optimizations, performance comparison, hardware proposal, conclusion.
11. Package deliverables into the Git repo

    script_<benchmark>.sh per benchmark (env setup, run, flame graph gen, post-opt run/compare).
    Optimized Python source, HW files, configs, logs.
    prompts.md (already being maintained per CLAUDE.md).
    README.md explaining repo structure and how to reproduce results.
    Commit incrementally with clear messages (bonus points for good history).
12. Prepare the presentation

    20–25 min walkthrough following the same flow: analysis → profiling → optimization → results → hardware proposal.
    Be ready for 5–10 min of Q&A; have working code on hand to demo.