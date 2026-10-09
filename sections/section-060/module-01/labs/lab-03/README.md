---
estimated_duration: 25m
---

# Repair A Broken Ingress Gateway Configuration Lab

In the `starfleet` namespace, requests from outside the cluster no longer reach `bridge`. The ingress gateway has a listener, but the `Gateway` and the `VirtualService` behind it hold more than one mistake.

Your job is to find every fault with the gateway's status codes, its access log, `istioctl analyze` and the gateway's own Envoy configuration. Fix the faults one at a time, and prove that requests from outside reach `bridge` again.

## Running the lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-01-03
```
