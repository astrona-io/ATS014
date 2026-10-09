---
estimated_duration: 20m
---

# Repair The Sealed Channel

Welcome to a repair mission, astronaut. On the planet `starfleet`, the shuttle sends open signals to a vault on the planet `outpost`, and its communications officer is supposed to seal them with TLS on the way out. Someone already wrote the three Istio objects for this, but every signal fails.

Your job is to find the two mistakes with the flight log and the shuttle's proxy, fix them, and prove that the vault was reached over a sealed channel. This lab needs no internet access: the vault runs inside the cluster.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-02-02
```
