---
estimated_duration: 3m
---

# Find The Missing Supply Ship

Welcome to a repair mission, astronaut. On the planet `starfleet`, the bridge page says "Error fetching product details". Every ship is running, every pod shows `2/2`, and `istioctl analyze` finds nothing wrong. Yet the bridge can no longer reach its supply ship, `cargo`.

Your job is to walk the fault-finding checklist, from `kubectl get` to the flight log and the shuttle's proxy, find the one value that is wrong, fix it, and prove the bridge can reach cargo again.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-000/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-000-01-02
```
