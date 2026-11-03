---
estimated_duration: 15m
---

# Keep Requests In The Client's Zone With trafficDistribution

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

In this lab, the `shuttle` pod in namespace `starfleet` runs in zone `zone-a`, and the `probe` Service has one pod in `zone-a` and one in `zone-b`. Requests from `shuttle` are spread over both zones.

Your job is to make the requests stay in `zone-a` with the Kubernetes `Service` field `trafficDistribution`, keep outlier detection in place for failover, and prove the result by counting which pods answer.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-05/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-05/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-05-02
```
