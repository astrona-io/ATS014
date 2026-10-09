---
estimated_duration: 15m
---

# Claim The Unclaimed Ingress

Welcome to a repair mission, astronaut. On the planet `starfleet`, an `Ingress` points at an ingress class that looks right, and still no signal gets through the arrival gate. There is no error anywhere.

Your job is to find out why no controller serves the `Ingress`, fix the ingress class, and prove that signals reach the echo probe through the gate.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-02-02
```
