---
estimated_duration: 5m
---

# Fail Over From A Failing Zone With Outlier Detection

In this lab, the endpoint in the client's own zone returns `503` to every request, yet it stays ready, so Kubernetes keeps it in the Service's endpoint list. Locality settings on their own never notice that.

Your job is to move the requests from the failing zone to the healthy one, by configuring outlier detection, the proxy feature that decides which endpoints count as failing.

## Launching the Lab

Run this command to start the cluster with the failing endpoint already in place:

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
