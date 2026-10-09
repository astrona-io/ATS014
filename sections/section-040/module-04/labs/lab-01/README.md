---
estimated_duration: 5m
---

# Locality Load Balancing And Failover

Welcome to a failover mission, astronaut. The ship in your own orbit answers `503` to every signal, yet it stays ready, so Kubernetes keeps it in the list. Locality settings on their own never notice that.

Your job is to make signals leave the failing orbit for the healthy one, by configuring the thing that decides what "failing" means.

## Launching the Lab

Run this command to start the cluster with the failing ship already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-04/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-04
```
