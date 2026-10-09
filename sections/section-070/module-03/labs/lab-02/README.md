---
estimated_duration: 3m
---

# Fix A ServiceEntry Selector And WorkloadEntry Labels Lab

This is a troubleshooting lab. Two pods in the `starfleet` namespace stand in for virtual machines outside Kubernetes. They were added to the mesh with two `WorkloadEntry` objects and a `ServiceEntry`, but every request to their host name, `freighter.starfleet.mesh`, fails with `503`. More than one setting is wrong.

## What you will practise

- Reading the `503 UH` response flag in the access log of the `shuttle` sidecar proxy.
- Listing the endpoints of a cluster with `istioctl proxy-config endpoints`.
- Comparing a `workloadSelector` with the labels of each `WorkloadEntry`.
- Choosing `MESH_INTERNAL` for machines you run yourself.

## Running the lab

Start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-03-02
```
