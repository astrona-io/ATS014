---
estimated_duration: 3m
---

# Fix One Ship's Star Chart

Welcome to a repair mission, astronaut. On the planet `starfleet`, the planet default `Sidecar` gives every ship a correct star chart. One ship, the shuttle, has its own `Sidecar` as well, and since then its signals to the probe on `outpost` vanish into a black hole.

Your job is to find out why the shuttle's own `Sidecar` lost those planets, repair it without removing it, and prove that the shuttle reaches the probe again.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-02-02
```
