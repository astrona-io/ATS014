---
estimated_duration: 45m
---

# Send One Ship Through The Departure Gate

Welcome to a build mission, astronaut. The solar system's departure gate (an egress gateway) is already running, and no signal goes through it yet. You will route one outside host through it, prove the hop from the gate's own flight log, and narrow the path to one spaceship (workload). Then you will see what "narrowed" really means: the other ship still reaches the host, directly.

This lab needs **no outbound internet access**. The "outside" endpoint is a pod deliberately left off the star chart (the mesh registry).

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-01
```
