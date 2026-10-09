---
estimated_duration: 30m
---

# Trigger A Route Timeout With A Scoped Delay Lab

In the `fault-demo` namespace, `booking-service` calls `notification-service` on every booking. You inject a delay and an abort on `notification-service` for one test user only, and put a timeout one hop above the delay so that the timeout fires on demand. Every other request must stay untouched.

The lab uses its own small app (`booking-service`, `notification-service` and a `tester` client), not the Starfleet.

## Running the lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-050/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-050-01
```
