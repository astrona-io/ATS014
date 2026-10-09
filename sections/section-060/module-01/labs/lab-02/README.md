---
estimated_duration: 15m
---

# Fix A Gateway Selector That Matches No Pod Lab

In the `starfleet` namespace, the ingress gateway gives no response to any request from outside the cluster. The `VirtualService` for `bridge` is correct, and a `Gateway` exists. But the gateway pods never got a listener on port `80`.

Your job is to find out why, using the gateway pod's labels, `istioctl analyze` and the gateway's own Envoy configuration. Then fix the `Gateway` and prove that requests from outside reach `bridge` again.

## Running the lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-01-02
```
