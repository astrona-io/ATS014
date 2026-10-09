---
estimated_duration: 45m
---

# Combine A Header Rule, A Weighted Canary And A Mirror Capstone Lab

This is the integration lab for traffic shifting. It puts both ways to test a new version on one `VirtualService` rule at the same time. A weighted canary split sends a share of real requests to the new version. A mirror sends a copy of the same requests to a separate shadow Service, whose responses no client ever sees.

The two features sit side by side on the same `http` rule and are easy to confuse. A mirror written as a `route` destination becomes part of a traffic split. A weighted destination written as a mirror never sends a response to the client.

There is no step-by-step guide until you have tried it. Work from the task.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with `istioctl install --set profile=demo`.
- The namespace `checkout` with `notification-service` v1 and v2 behind one Service, a separate `notification-shadow` Deployment and Service, and a `tester` client pod.
- No `DestinationRule` and no `VirtualService`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-020
```
