---
estimated_duration: 20m
---

# Split TCP Connections 80/20 Between Two Subsets Lab

This graded lab checks one skill: writing a weighted `tcp` route and proving that it splits connections, not requests.

> **Status: UNTESTED.** This lab was written without being run. Its grader and its reference solution have not been tried on a cluster yet.

## What you will practise

In the `starfleet` namespace, the `probe` pods run in two versions, `v1` and `v2`. A Service named `probe-tcp` already selects both versions, and its port is named `tcp`, so Istio treats traffic to it as plain TCP. There is no `DestinationRule` and no `VirtualService` for it. You define the two subsets and write a `tcp` route that sends 80% of the connections to `v1` and 20% to `v2`.

The grader does not just look for the objects. It sends many fresh connections from the `shuttle` pod and counts which version answered.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm, and `istioctl` ready to use.
- The namespace `starfleet` with `probe` v1 and v2, the Services `probe` (port named `http`) and `probe-tcp` (port named `tcp`), the `shuttle` client and access logs switched on.
- No `DestinationRule` and no `VirtualService`.

## Running the lab

Start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-03-01
```
