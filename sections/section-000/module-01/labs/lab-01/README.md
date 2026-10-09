---
estimated_duration: 3m
---

# Bring Workloads Into The Mesh With Sidecar Injection Lab

This graded lab checks one skill that every later lab depends on: telling whether a workload is really part of the Istio mesh.

## What you will practise

Istio adds a **sidecar proxy** (Envoy) to each pod in the mesh, as an extra container next to the application. All traffic in and out of the pod passes through it, and Istio's control plane, `istiod`, sends it its configuration. The workloads that have a sidecar proxy form the **mesh**.

A pod without a sidecar proxy still runs, and its requests still work. But Istio cannot see that traffic or apply any rule to it, and nothing warns you about it.

In this lab every pod is `Running` and every request succeeds. Even so, **two workloads run outside the mesh.** Your task is to find them and bring them in, without replacing them with new Deployments.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- Two namespaces with workloads: `mesh-demo` and `legacy-app`.
- No hints about what is wrong. Kubernetes reports everything as healthy.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-000/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-000-01
```
