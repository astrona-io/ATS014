---
estimated_duration: 15m
---

# Open The Closed Gate

Welcome to a repair mission, astronaut. On the planet `starfleet`, the spaceport arrival gate gives no reply to any signal from outside. The flight plan for the bridge is correct, and a `Gateway` exists. But the gate itself never opened.

Your job is to find out why the gate has no listener, using the gateway pod's labels, `istioctl analyze` and the gateway's own proxy. Then fix the `Gateway` and prove that signals from outside reach the bridge again.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-01-02
```
