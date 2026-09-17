The Raytrace directory:
*All files are in the same directory except for reports that each has a corresponding directory


Program files:
1. simpleRaytrace.py	 	- the original Python benchmark code
2. Praytrace.py 	 		- the optimized code that runs pyperf, but uses a C library we defined.
3. Craytrace.c 				- the C implementation of the functionality.
4. CraytraceLib.dll			- the compiled dynamic-link-library, used for testing in Windows environment.
5. CraytraceLib.so 			- the compiled dynamic-link-library, used for running in a Linux environment (on the server).
6. BareSimpleRaytrace.py	- a version of the original implementation we made that runs without pyperf, to check the stats of the naked function.
7. BareCraytrace.c 			- a version of the optimized implementation we made that runs without pyperf, to check the stats of the naked function.
8. ppmViewer.py 			- initially we didn't manage to see the pixel maps, so we made this file that allows us to see the result (to make sure we are still getting the same output).


Scripts:
1. run_perf.sh 				- runs perf for both simpleRaytrace, it also get Flame graphs, outputs to directory \profile_results.
2. run_bare_perf.sh			- runs perf for the bare implementations, outputs to directory \profile_results.
3. get_python_salls.sh 		- gets the Python functions call-stack for simpleRaytrace.py as requested for at the first page of the project's description, outputs to \perf_py_reports.
4. get_python_salls2.sh 	- gets the Python functions call-stack for simpleRaytrace.py as requested for at the first page of the project's description, outputs to \perf_py_reports.
5. memory_usage.sh			- runs valgrind to check memory usage of the bare implementations.



Output files:
profile_results
			1. simpleRaytrace.py_perf_stat.txt		- perf's results on the original program.
			2. simpleRaytrace.py_flamegraph.svg 	- the Flamge graph of the original program.
			3. Praytrace.py_perf_stat.txt			- perf's results on the optimized program.
			4. Praytrace.py_flamegraph.svg 			- the Flame graph of the optimized program.
			
			5. BareSimpleRaytrace_perf_stat.txt		- perf's results on the bare original program.
			6. BareSimpleRaytrace_flamegraph.svg	- the Flame graph of the bare original program.
			7. BareCraytrace_perf_stat.txt 			- perf's results on the bare optimized program.
			
perf_py_reports
			1. perf_Praytrace.data					- the raw data.
			2. perf_report_Praytrace.txt			- the Python functions call-stack of the optimized program.
			3. perf_report_simpleRaytrace.txt		- the Python functions call-stack of the original program.
			4. perf_simpleRaytrace.data 			- the raw data.

memory_results
			1. time_py.txt							- timing results of the bare original implementation.
			2. time_c.txt 							- timing results of the bare optimized implementation.
			3. valgrind_py.txt						- memory usage results of the bare original implementation.
			4. valgrind_c.txt						- memory usage results of the bare optimized implementation.
