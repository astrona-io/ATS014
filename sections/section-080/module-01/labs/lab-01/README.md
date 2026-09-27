# Route External Traffic Through An Egress Gateway Sandbox

Welcome to the Module 1 targeted practice sandbox. An egress gateway is already running and carrying nothing. You'll route one external host through it, prove the hop happened from the gateway's own log, and restrict the path to one workload — then see what "restricted" really means.

This lab needs **no outbound internet access**: the "external" endpoint is a pod deliberately kept out of the mesh registry.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```
