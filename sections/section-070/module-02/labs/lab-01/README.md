---
estimated_duration: 30m
---

# Seal Signals To A Secure Planet

Welcome to your mission, astronaut. The endpoint you must reach accepts **only** sealed signals (TLS), and the client calls it over plain `http://`. The sidecar, your ship's communications officer, has to seal each signal on the way out. The endpoint itself reports which scheme it was reached over, so there is no guessing whether it worked.

This lab needs **no outbound internet access**: the TLS endpoint runs inside the cluster, outside the mesh registry.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-02
```
