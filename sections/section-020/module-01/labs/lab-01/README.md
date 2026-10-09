---
estimated_duration: 30m
---

# Run A Canary With A Header Rule Above The Split Lab

This graded lab checks the core canary skill: sending a set share of requests to a new version, while a group of testers always reaches the new version.

## What you will practise

A **canary release** sends a small share of requests to a new version before all traffic moves to it. In Istio you build it from two objects. A `DestinationRule` defines **subsets**, named groups of a Service's pods selected by a label. A `VirtualService` sends requests to those subsets, and its `weight` field sets each destination's share.

The `http` rules of a `VirtualService` are checked from the top, and the first rule that matches wins. A header rule placed above the weighted rule therefore takes the testers' requests out of the split. The share is set by the weights only, never by the number of pods, so the lab also checks that you did not scale any Deployment.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- The namespace `shifting-demo` with `notification-service` v1 and v2 (one replica each) behind one Service, and a `tester` client pod.
- No `VirtualService` and no `DestinationRule`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-01
```
