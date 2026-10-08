# Route External Traffic Through An Egress Gateway Sandbox

Welcome to the Module 1 practice mission, astronaut. The solar system's departure gate (an egress gateway) is already running, and no signal goes through it yet. You will route one external host through it, prove the hop from the gate's own flight log, and restrict the path to one spaceship (workload). Then you will see what "restricted" really means.

This lab needs **no outbound internet access**. The "external" endpoint is a pod deliberately left off the star chart (the mesh registry).

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```
