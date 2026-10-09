---
estimated_duration: 3m
---

# Troubleshoot A Mirror That Sends No Copies Lab

This graded lab checks one skill: finding out why a mirror sends no copies when the client gets normal responses.

## What you will practise

In the `starfleet` namespace, a `VirtualService` routes every request to `probe` v1 and mirrors every request to `probe` v2. The release candidate `probe-v2` should receive a copy of every request, and it receives nothing. Clients get correct responses, so nothing looks wrong.

You find the cause with three checks: the mirror policy in the proxy of `shuttle`, the endpoints of the mirror cluster, and `istioctl analyze`. Then you fix it and prove that the copies arrive.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm, and `istioctl` ready to use.
- The namespace `starfleet` with `probe` v1 and v2, the `shuttle` client and access logs switched on.
- A `VirtualService` and a `DestinationRule` named `probe`, with the fault already in place.

## Running the lab

Start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-02-02
```
