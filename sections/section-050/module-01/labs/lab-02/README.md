---
estimated_duration: 20m
---

# Inject A Delay And An Abort Lab

In the `starfleet` namespace, the team wants to know how the services behave when something goes wrong. You inject two faults with `VirtualService` objects: a delay that makes `navcom` slow, and an abort that makes `probe` look down.

Your job is to write both faults, and to prove from the access logs that the sidecar proxy of the right client applied each one.

## Running the lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-050/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-050-01-02
```
