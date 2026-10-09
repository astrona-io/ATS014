---
estimated_duration: 20m
---

# Fix The Broken Flight Plans

Welcome to a repair mission, astronaut. On the planet `starfleet`, the gate is built and working, but signals through it never reach the bridge or the scout. Two flight plans dock at the gate, and each one is broken in its own way.

Your job is to read the status lights of both `HTTPRoute` objects, find each fault, fix it without touching the gate, and prove that signals reach both ships.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03-03
```
