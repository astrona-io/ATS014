---
estimated_duration: 15m
---

# Retry Only The Signals Worth Re-Sending

Welcome to a tuning mission, astronaut. On the planet `starfleet`, the probe's communications officer re-sends every failed signal three times, even the ones that will fail the same way forever. Your job is to narrow the retry policy to the one failure worth another try, and to prove it by counting the signals at the probe.

## Launching the Lab

Run this command to start the cluster with the starting policy in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-01-03
```
