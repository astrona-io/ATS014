---
estimated_duration: 3m
---

# Fix The Docking Instructions

Welcome to a repair mission, astronaut. On the planet `starfleet`, every signal that `jason` sends to the scout beacon fails with `503`. The flight plan is correct. Somewhere in the docking instructions, one value points at ships that do not exist.

Your job is to find that value with the flight log, `istioctl analyze` and the shuttle's proxy, fix it, and prove that jason's signals land on `scout-v2` again.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-03
```
