---
estimated_duration: 3m
---

# Find Out Why The Flight Plan Does Nothing

Welcome to a repair mission, astronaut. On the planet `starfleet`, the scout flight plan was supposed to send `jason` to `scout-v2` and everyone else to `scout-v1`. Instead, every signal lands on a random scout ship. `kubectl` accepted the flight plan without a word, and `istioctl analyze -n starfleet` finds nothing wrong.

More than one thing is wrong with it. Your job is to find every fault with `kubectl get -A`, `istioctl analyze`, the shuttle's flight log and the proxy's own orders, repair the flight plan, and prove that every signal lands on the right ship class.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-04
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-04
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-04
```
