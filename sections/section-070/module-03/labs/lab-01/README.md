# Add External Workloads With WorkloadEntry Sandbox

Welcome to the Module 3 targeted practice sandbox, astronaut. Two machines sit outside Kubernetes with nothing but IP addresses, like old ships outside the fleet's signal network. You'll give them a hostname, a mesh identity and a place on the star chart (the registry) — so that everything else in this course applies to them.

This lab needs **no outbound internet access**: the "virtual machines" are uninjected pods.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-01
```
