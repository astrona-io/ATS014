---
estimated_duration: 30m
---

# Expose A Service With A Kubernetes Ingress

Welcome to your graded mission, astronaut. You'll have Istio's gateway serve a plain Kubernetes `Ingress`: an ingress class it answers, host and path rules with two path types, and TLS with the secret on the planet where the gate can read it. That last part catches almost everybody the first time.

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
