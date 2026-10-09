---
estimated_duration: 20m
---

# Fix Two Broken HTTPRoutes From Their Status Conditions Lab

A troubleshooting lab. In the `starfleet` namespace, a Gateway API `Gateway` runs and works, but requests through it never reach the `bridge` or the `scout` Service. Two `HTTPRoute` objects are meant to attach to the `Gateway`, and each one has a different fault.

The learner reads the status conditions of both `HTTPRoute` objects, finds each fault, fixes it without changing the `Gateway`, and proves that requests reach both Services.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03-03
```
