---
estimated_duration: 30m
---

# Expose A Service With A Kubernetes Ingress

In this lab, Istio's ingress gateway serves a plain Kubernetes `Ingress`. You create an `IngressClass` that Istio serves, host and path rules with two path types, and TLS with the secret in the namespace where the gateway can read it. Most people get that last step wrong the first time.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-02
```
