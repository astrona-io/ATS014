---
estimated_duration: 3m
---

# Declare A Service Port As HTTP

In the namespace `starfleet`, a `VirtualService` for the `probe` echo server should send every request with the header `x-mission: test` to `probe-v2`, and every other request to `probe-v1`. The `VirtualService` is correct. `kubectl` accepted it, and `istioctl analyze` finds nothing wrong. Yet requests still reach both versions.

The port declaration of the `probe` Service has switched the `VirtualService` off. Your job is to find it with the route table and the listener of the `shuttle` proxy, declare the port as HTTP again, and prove that every request reaches the right version.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-05
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-01/labs/lab-05
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-01-05
```
