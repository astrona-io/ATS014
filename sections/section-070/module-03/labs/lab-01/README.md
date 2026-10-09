---
estimated_duration: 3m
---

# Add Two Virtual Machines To The Mesh With WorkloadEntry Lab

This is a build lab. Two pods in the `vm-demo` namespace stand in for virtual machines outside Kubernetes: they have IP addresses, but no sidecar proxy and no Service. You give them one host name, a mesh identity and a place in Istio's service registry, so that every mesh rule can apply to them.

This lab needs **no outbound internet access**: the "virtual machines" are pods without a sidecar proxy.

## What you will practise

- Writing `WorkloadEntry` objects with an address, a label and a ServiceAccount.
- Selecting those entries with a `MESH_INTERNAL` `ServiceEntry` and a `workloadSelector`.
- Writing the `WorkloadGroup` template that real virtual machines register against.
- Proving the result with a request by host name and the proxy's endpoint list.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-03
```
