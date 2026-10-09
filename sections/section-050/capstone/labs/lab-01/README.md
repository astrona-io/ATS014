---
estimated_duration: 45m
---

# Test Retries And Timeouts With Scoped Faults Capstone Lab

This is the capstone lab of the section on fault injection. It uses faults for their real purpose: to test resilience settings. You inject two faults at the same time on one host, an abort next to a retry policy and a delay below a timeout. Each fault matches only requests with its own header, so no other client in the namespace is affected.

The result of the first test is the interesting part, and it is not what most people expect. Work from the task first, and open the walkthrough only after you have tried it.

The lab uses its own small app (`booking-service`, `notification-service` and a `tester` client in the `orders` namespace), not the Starfleet.

## Running the lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-050/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-050
```
