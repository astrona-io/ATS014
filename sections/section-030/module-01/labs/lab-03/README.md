---
estimated_duration: 3m
---

# Spread Requests Evenly With ROUND_ROBIN Lab

A troubleshooting lab. In the `starfleet` namespace, the `probe` Service has four pods, but every request from the `shuttle` pod lands on the same one. The other three pods get no traffic.

The learner finds the cause in the `probe` `DestinationRule` and in the `shuttle` pod's proxy configuration, then changes the load balancer policy so the requests are spread over all four pods, in turn.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-01-03
```
