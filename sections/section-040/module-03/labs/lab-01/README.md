---
estimated_duration: 3m
---

# Eject A Failing Endpoint On A Two-Endpoint Service Lab

This graded lab checks one skill: making a client's sidecar proxy stop sending requests to an endpoint that keeps failing, while Kubernetes still lists that endpoint as ready.

## What you will practise

**Outlier detection** is an Istio setting in a `DestinationRule`. The client's sidecar proxy (Envoy) counts the error responses from each endpoint. When one endpoint fails too often in a row, the proxy removes it from its own load-balancing pool for a while. This is called an **ejection**.

The Service in this lab has only two endpoints. That makes one field, `maxEjectionPercent`, decide whether an ejection can happen at all.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use.
- The namespace `outlier-demo` with an `httpbin` Service, one healthy pod, one pod that answers every request with `503`, and a `tester` client pod.
- No `DestinationRule`. About half of all requests fail.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-03
```
