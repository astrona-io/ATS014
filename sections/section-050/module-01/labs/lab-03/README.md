---
estimated_duration: 15m
---

# Scope A Forgotten Abort To One Test User Lab

In the `starfleet` namespace, somebody injected an abort fault on `navcom` and never removed it. Every response from `scout` now arrives without its star ratings, for every client in the namespace.

Your job is to keep the fault for test requests only, with a header match, and to give every other request its star ratings back.

## Running the lab

Run this command to start the cluster with the problem already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-050/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-050-01-03
```
