---
estimated_duration: 15m
---

# Repair A Workload-Selected Sidecar Lab

This graded lab practises one rule of the `Sidecar` resource: a `Sidecar` with a `workloadSelector` replaces the namespace-wide `Sidecar` for the pods it selects, and takes nothing from it.

## What you will practise

In the `starfleet` namespace, the namespace-wide `Sidecar` gives every proxy correct configuration. The `shuttle` pod also has its own `Sidecar`, and since then its requests to the `probe` Service in `outpost` end in the `BlackHoleCluster`.

Your task is to find out why the `shuttle` pod's own `Sidecar` lost those hosts, repair it without removing it, and prove that `shuttle` reaches `probe` again through the `probe` cluster.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm, and access logs switched on for every proxy.
- `starfleet` (`shuttle`, `cargo`) and `outpost` (`probe` v1 and v2), both with sidecar injection.
- Two `Sidecar` objects in `starfleet`: `default` (correct) and `shuttle-only` (the fault).

## Running the lab

Start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-02-02
```
