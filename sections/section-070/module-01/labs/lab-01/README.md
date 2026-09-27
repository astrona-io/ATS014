# Control External Access With ServiceEntry Sandbox

Welcome to the Module 1 targeted practice sandbox. The mesh is already deny-by-default, so every external destination is refused. You'll register exactly one of them, prove the other is still blocked, and then put a timeout on the one you allowed — because a registered host is an ordinary host.

This lab needs **no outbound internet access**: the "external" endpoints are ordinary pods deliberately left out of the mesh registry.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-01
```
