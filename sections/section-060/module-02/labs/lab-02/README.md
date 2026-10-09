---
estimated_duration: 15m
---

# Fix An IngressClass That No Controller Serves

This is a troubleshooting lab. In the `starfleet` namespace, an `Ingress` points at an ingress class that looks right, and still no request gets through Istio's ingress gateway. There is no error anywhere.

Your job is to find out why no controller serves the `Ingress`, fix the `IngressClass`, and prove that requests reach the `probe` Service through the gateway.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-02-02
```
