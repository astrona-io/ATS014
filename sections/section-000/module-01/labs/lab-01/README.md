---
estimated_duration: 3m
---

# Which Workloads Are Actually In The Mesh Sandbox

Astronaut, this is your first graded mission. It checks one skill that every later mission depends on: telling whether a workload is really part of the Istio mesh.

## What you will practise

Istio works by putting a small helper program, a **sidecar proxy**, next to each of your app's containers. Think of each pod as a spaceship, and the sidecar as the ship's communications officer. Every signal in or out goes through the communications officer, and Istio's mission control tells them the rules to follow. Istio calls the fleet of workloads that have one a **mesh**.

A ship without a communications officer still flies. Its calls still work. But Istio cannot see them or apply any rule to them, and nothing warns you about it.

In this lab, every pod is `Running` and every request succeeds. Even so, **two workloads are flying outside the mesh.** Your mission is to find them and bring them in, without replacing them with new ships.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- Two namespaces (two planets) with workloads on them: `mesh-demo` and `legacy-app`.
- No hints about what is wrong. Kubernetes reports everything as healthy.
