# Prompts

1. On this machine there is already an ssh config for the QEMU server in this course. Can you find it?
2. what's the password to oriedu@naranja4.cslcs.technion.ac.il
3. ➜  ~ ssh qemu-naranja
   channel 0: open failed: connect failed: Connection refused
   stdio forwarding failed
   Connection closed by UNKNOWN port 65535
   ➜  ~
4. why don't you have access to that terminal?
   I want you to have access to this environment so you can run things for me
5. now the server is just failing, both the naranja4 and the qemu
6. okay, I'm back in qemu, what to do now
7. done
8. I want to set up this repo in the vm. Can you scp it ?
9. yes. I want to first get rid of the Nbody experiment. I had to change experiments.
   Let's pick a new one from the list on @Project.pdf
10. (in response to clarifying questions on which benchmark to pick) Give me a list of all the benchmarks. My partner is doing raytrace for the second one / Raytrace
11. what hardware accelerator could be possible with deepblue
12. explain go benchmark
13. What hardware accelerator can we use for go
14. give me the analysis for picke_dict
15. let's analyze sqlite_synth
16. it seems that you think pyflate is the best idea
17. let's go with pyflate
18. (in response to a clarifying question on how to handle the old Nbody folder) Delete it entirely
19. also remove the commits from git history
20. just open a dict.
    Afterwards we want to get baseline results.
21. let's get a flame graph.
    What command are you running to get this?
22. the flame graph has nonsensical names. Why is this happening? Is the code C compiled?
    Maybe we should run with pypy?
23. yes, install py-spy and generate the python-level flame graph. Also delete the old
    benchmark data, flame graph, the whole lot
24. What benchmarks did I get besides the flamegraph? I want branch misses, cycles,
    the usual stuff. Is this available?
25. can you add a file called performace-analyze that has scripts that do all of these runs?
    the py-spy to get the flame graph, and perf stat -r 3, all of the things we did in this
    session
26. I want to present the baseline results. Give me some metrics from the results in a table.
27. You have been given comments on the previous commits you made in the repository.
    @copilot resolve the merge conflicts in this pull request
28. currently, I want to actually make the changes. look in my presentation, I explained
    the two software areas I want to improve
29. what are the current files that are changed?
30. what are these new python files? what do they do?
31. commit them, then rebase from main. and then push my changes
32. Read @Project.pdf what's missing from the assignment requirements?
33. I am responsible for the pyflate section. Let's focus just on that. Has  the software improvement been made?
34. where does the changed code sit in our repo?
35. So how were the measurements done on this new file? with py-spy?
36. now it should be up, if not you have instructions to raise it
37. yes fix it
38. Okay, what's next?
39. First explain exactly what the script will do
40. Does the script generate the report as appears in page 1 of the instructions?
41. what is the dwarf test ?
42. what fields should the report show that currently don't work?
43. wait for the dwarf result then write the script
44. yes run it on the VM
45. yes