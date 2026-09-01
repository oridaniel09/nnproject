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
9. now I want to run pyperformance on it, I want to use the benchmark Nbody
10. pyperformance: error: unrecognized arguments: --values 10 --loops 1
11. where does it save the results?
12. (pyperf-venv) root@ubuntu:~/nnproject# python -m pyperf system tune
    Tune the system configuration to run benchmarks
    ...
    Errors
    ======
    Turbo Boost (MSR): Failed to read MSR 0x1a0 from /dev/cpu/0/msr: [Errno 2] No such file or directory: '/dev/cpu/0/msr'
    Turbo Boost (MSR): Try to load the msr kernel module: sudo modprobe msr
    (pyperf-venv) root@ubuntu:~/nnproject#

    Maybe I forgot something in the configuration - as per the pdfs given to me
13. Maybe I missed something in the configuration - as per the pdfs given to me
