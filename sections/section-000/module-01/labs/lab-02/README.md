---
estimated_duration: 3m
---

# Fix A Service Selector That Matches No Pod Lab

In the `starfleet` namespace, the `bridge` page says "Error fetching product details". Every pod is running, every pod shows `2/2`, and `istioctl analyze` finds nothing wrong. Yet the `bridge` workload can no longer reach the `cargo` Service.

Your job is to walk the fixed order of checks, from `kubectl get` to the access log and the `shuttle` sidecar proxy. Find the one value that is wrong, fix it, and prove that `bridge` can reach `cargo` again.

## Running the lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-000/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-000-01-02
```
