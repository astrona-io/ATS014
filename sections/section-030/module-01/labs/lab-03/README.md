---
estimated_duration: 3m
---

# Spread The Signals Evenly

Welcome to a repair mission, astronaut. On the planet `starfleet`, the probe squadron has four ships, but every signal from the shuttle lands on the same one. The other three sit idle.

Your job is to find out why, with the docking instructions and the shuttle's proxy, and change the policy so the signals are spread across the whole squadron, in turn.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-01-03
```
