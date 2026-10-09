---
estimated_duration: 20m
---

# Fix A Broken TLS Origination

In `starfleet`, the `shuttle` sends plain HTTP requests to a TLS-only `vault` pod in `outpost`, and its sidecar proxy should originate TLS (open the TLS connection itself) on the way out. The three Istio objects for this already exist, but every request fails.

The task is to find the two mistakes with the access log and the shuttle's proxy configuration, fix them, and prove that the vault received the request over TLS. This lab needs no internet access: the vault runs inside the cluster.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-02-02
```
