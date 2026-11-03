---
estimated_duration: 45m
---

# Compose A Delegated Canary With Scoped Visibility Capstone Lab

This is the second integration lab for routing. It puts the skills of the delegate and `exportTo` module together: a root `VirtualService` that hands the paths `/hostname` and `/delay` to two delegates, a header rule inside each delegate, subsets, a timeout that depends on the header, and an `exportTo` list that limits the objects to two of the three namespaces.

> **Status: UNTESTED.** This lab was written without being run. Its grader and its reference solution have not been tried on a cluster yet.

There is no step-by-step guide until you have tried it. Work from the task.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm (`istio-base` and `istiod`).
- The namespace `starfleet` with `probe` v1 and v2 behind the Service `probe` (port `8000`), and a `shuttle` client.
- The namespaces `dock` and `depot`, each with sidecar injection and a `shuttle` client.
- No `DestinationRule` and no `VirtualService`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/capstone/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/capstone/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-010-02
```
