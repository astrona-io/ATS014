---
estimated_duration: 3m
---

# Which Workloads Are Actually In The Mesh Sandbox

This is the first graded lab in the course. It checks one skill that every later lab depends on: telling whether a workload is really part of the Istio mesh.

## What you will practise

Istio works by putting a small helper program, a **sidecar proxy**, next to each of your app's containers. Think of it as a receptionist who sits in front of every office. Every call in or out goes through the receptionist, and Istio gives the receptionist the rules to follow. Istio calls the group of workloads that have one a **mesh**.

A workload without a sidecar still runs. Its calls still work. But Istio cannot see them or apply any rule to them, and nothing warns you about it.

In this lab, every pod is `Running` and every request succeeds. Even so, **two workloads are outside the mesh.** Your job is to find them and bring them in, without replacing them with new ones.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- Two namespaces with workloads in them: `mesh-demo` and `legacy-app`.
- No hints about what is wrong. Kubernetes reports everything as healthy.

The full task, with the exact rules the grader checks, is in [`question.md`](question.md). Try it without the walkthrough first. When you are done, or stuck, [`solution.md`](solution.md) goes through it step by step.

## Before you start

Read the module this lab belongs to: [How A Request Moves Through The Mesh](../../course.md). Part 3, [The Diagnostic Toolkit](../../course-03-the-diagnostic-toolkit.md), shows the commands you will need here.

## Launching the Lab

Run this command to start the cluster and set up the workloads:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-000/module-01/labs/lab-01
```

The grader looks at the running pods and asks Istio's control plane which workloads it can see. Adding a label alone will not pass. The pods must really have their sidecar.

To remove the lab when you are done:

```bash
astrona destroy ats-014-lab-000-01
```

## Official docs

- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/): how a workload gets its sidecar, and how it can opt out
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/): how to ask Istio which workloads it knows about
