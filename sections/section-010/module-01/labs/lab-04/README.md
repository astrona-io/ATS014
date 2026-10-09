---
estimated_duration: 3m
---

# Fix A VirtualService That Does Not Apply

In the namespace `starfleet`, the `scout` `VirtualService` should send requests from `jason` to `scout-v2` and every other request to `scout-v1`. Instead, every request lands on a random `scout` version. `kubectl` accepted the `VirtualService` with no warning, and `istioctl analyze -n starfleet` finds nothing wrong.

The `VirtualService` has more than one fault. Your job is to find every fault with `kubectl get -A`, `istioctl analyze`, the access log of the `shuttle` proxy and `istioctl proxy-config`, repair the `VirtualService`, and prove that every request reaches the right version.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-04
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-04
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-04
```
