---
estimated_duration: 25m
---

# Repair The Arrival Gate

Welcome to a repair mission, astronaut. On the planet `starfleet`, signals from outside the solar system no longer reach the bridge. The gate is open, but the `Gateway` and the flight plan behind it hold more than one mistake.

Your job is to find every fault with the gate's answers, its flight log, `istioctl analyze` and the gateway's own proxy. Fix them one at a time, and prove that signals from outside reach the bridge again.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-01-03
```
