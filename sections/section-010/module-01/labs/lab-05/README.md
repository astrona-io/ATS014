---
estimated_duration: 3m
---

# Bring HTTP Routing Back

Welcome to a repair mission, astronaut. On the planet `starfleet`, a flight plan for the echo probe is supposed to send every signal marked `x-mission: test` to `probe-v2`, and every other signal to `probe-v1`. The flight plan is correct. `kubectl` accepted it, and `istioctl analyze` finds nothing wrong. Yet the signals still land on both probe ships.

One word somewhere else has switched the flight plan off. Your job is to find it with the shuttle's route table and the listener, bring HTTP routing back, and prove that every signal lands on the right ship class.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-05
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-05
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-05
```
