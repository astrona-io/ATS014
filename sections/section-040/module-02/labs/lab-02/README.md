---
estimated_duration: 3m
---

# Calm The Retry Storm

Welcome to a repair mission, astronaut. On the planet `starfleet`, the probe is struggling and answers with `503`. Its shields are fine. The trouble is the flight plan: its retry policy sends every failing signal again and again, so the struggling probe gets six times the work.

Your job is to change the retry policy so that a second try only happens for signals that never reached the probe, and to prove that each failing signal now reaches the probe exactly once.

## Launching the Lab

Run this command to start the cluster with the storm already raging:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-02-02
```
