---
estimated_duration: 25m
---

# Repair The Departure Gate

Welcome to a repair mission, astronaut. Signals from the planet `starfleet` to the relay should leave through the departure gate (the egress gateway), so one flight log records every one of them. The route is written, and the relay answers. But the gate's flight log stays empty.

Your job is to find out why with the flight logs and the proxies' configuration, fix every fault, and prove that the signal really flies through the gate. This lab needs no outbound internet access.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-01-02
```
