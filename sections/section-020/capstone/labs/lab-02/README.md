---
estimated_duration: 40m
---

# Combine An HTTP Canary, A Mirror And A TCP Split Capstone Lab

This is the second integration lab for traffic shifting. It puts the HTTP skills (a header rule, a weighted canary and a mirror) next to the TCP skill (a weighted `tcp` route) on the same pods, and asks you to prove that the two kinds of split count different things: requests and connections.

> **Status: UNTESTED.** This lab was written without being run. Its grader and its reference solution have not been tried on a cluster yet.

There is no step-by-step guide until you have tried it. Work from the task.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with `istioctl install --set profile=demo`.
- The namespace `starfleet` with `probe` v1 and v2, a Service `probe` (port named `http`) and a Service `probe-tcp` (port named `tcp`) for the same pods, a separate `probe-shadow` Deployment and Service, and the `shuttle` client.
- No `DestinationRule` and no `VirtualService`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/capstone/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/capstone/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-020-02
```
