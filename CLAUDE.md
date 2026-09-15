In this repo we will implement the project described in @Project.pdf
The first step is to configure the pyperformance in a virtual environment.
All prompts made should be saved to the file @prompts.md

How to connect to machine:
First check if the machine is up:
ssh qemu-naranja

If this fails, the qemu machine needs to be booted
the first step is entering the naranja4 vm:
ssh naranja4
inside, we run:
qemu-system-x86_64 -m 4096m -nographic -cpu host,pmu=on -accel kvm     -nic user,model=virtio-net-pci,hostfwd=tcp::12028-:22     -drive file=jammy-server-cloudimg-amd64-disk-kvm.img,format=qcow2

which boots the qemu
the creds are:
username: root
password: ubuntu

preferably run this in a seperate terminal or tmux.
