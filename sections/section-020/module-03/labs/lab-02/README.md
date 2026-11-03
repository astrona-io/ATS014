---
estimated_duration: 15m
---

# Fix A TCP Split That Never Happens Lab

This graded lab checks one skill: finding why a weighted `tcp` route does not split connections, and fixing every cause.

> **Status: UNTESTED.** This lab was written without being run. Its grader and its reference solution have not been tried on a cluster yet.

## What you will practise

In the `starfleet` namespace, a `VirtualService` for `probe-tcp` has a `tcp` route that should send 80% of the connections to `probe` v1 and 20% to `probe` v2. The split never happens. The `VirtualService` looks correct, and connections still work, so nothing reports an error.

You find the causes with the route table, the listener and the endpoints of the proxy of `shuttle`, and with `istioctl analyze`. Then you fix them and prove the split with many fresh connections.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm, and `istioctl` ready to use.
- The namespace `starfleet` with `probe` v1 and v2, the Service `probe`, the `shuttle` client and access logs switched on.
- A Service, a `DestinationRule` and a `VirtualService` named `probe-tcp`, with the faults already in place.

## Running the lab

Start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-03-02
```
