---
estimated_duration: 30m
---

# Route To v1 And Mirror Every Request To v2 Lab

This graded lab checks one skill: sending every client request to a stable version while a copy of each request goes to a release candidate.

## What you will practise

Mirroring means that the sidecar proxy of the client pod sends each request to the normal destination and also sends a copy to a second destination, the shadow. The proxy throws away the shadow's response, so no client ever sees it.

You write a `DestinationRule` with the subsets `v1` and `v2`, and a `VirtualService` that routes every request to `v1` and mirrors every request to `v2`. Then you prove two things: every client response comes from `v1`, and `v2` really receives the copies. The client's output cannot prove the second part, so you read the access log of the `v2` sidecar proxy.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- The namespace `mirror-demo` with `notification-service` v1 and v2 behind one Service, and a `tester` client pod.
- No `DestinationRule` and no `VirtualService`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-02
```
