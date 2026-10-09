---
estimated_duration: 3m
---

# Fix A DestinationRule Subset That Selects No Pods

In the namespace `starfleet`, every request that the user `jason` sends to the `scout` Service fails with `503`. The `VirtualService` is correct. One label value in the `DestinationRule` selects no pod.

Your job is to find that value with the access log, `istioctl analyze` and the proxy of the `shuttle` pod, fix it, and prove that requests from `jason` reach `scout-v2` again.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-03
```
