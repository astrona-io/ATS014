---
estimated_duration: 30m
---

# Pin A Subset By Header And Override Another Subset Lab

A build lab. The learner pins users to endpoints with consistent hashing at host level, then overrides that policy for one subset only with `ROUND_ROBIN`. The learner proves from the proxy's own configuration that the two subset clusters really use different algorithms, and proves the behaviour with live requests.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-01
```
