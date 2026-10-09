---
estimated_duration: 30m
---

# Limit A Namespace's Proxy Configuration With A Sidecar Lab

This graded lab practises the `Sidecar` resource: the Istio object that limits which hosts `istiod` sends to the sidecar proxies in a namespace.

## What you will practise

By default, every sidecar proxy holds a cluster for every Service in the mesh. In this lab you write a namespace-wide `Sidecar` that keeps only the proxy's own namespace, `istio-system` and one other namespace. You then prove the change from the proxy's own cluster list, and show with live requests that a third namespace is no longer reachable.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed and `istioctl` ready to use. The mesh uses `outboundTrafficPolicy: REGISTRY_ONLY`.
- Three namespaces with sidecar injection: `sidecar-demo` (`tester` and `local-backend`), `sidecar-other` (`httpbin`) and `sidecar-third` (`httpbin`).
- No `Sidecar` resource.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-02
```
