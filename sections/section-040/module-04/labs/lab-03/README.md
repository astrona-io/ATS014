---
estimated_duration: 5m
---

# Split Signals Between Two Orbits

Welcome to a flight-planning mission, astronaut. On the planet `starfleet`, the shuttle keeps every signal to the probe in its own orbit. That is fast, but the probe in the far orbit receives nothing, so nobody knows whether the path to it still works.

Your job is to replace the preference with a fixed split: most signals stay close, and a set share flies to the far orbit on purpose.

## Launching the Lab

Run this command to start the cluster in its starting state:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-04/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-04-03
```
