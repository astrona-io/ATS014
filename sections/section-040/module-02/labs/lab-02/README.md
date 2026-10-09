---
estimated_duration: 20m
---

# Limit Retries To Connection Failures Lab

In the `starfleet` namespace, the `probe` Service is struggling and answers with `503`. Its connection pool limits in the `DestinationRule` are correct. The problem is the retry policy in the `probe` `VirtualService`: it sends every failing request again and again, so the struggling service gets six times the work.

Your job is to change the retry policy so that the client proxy retries only requests that never reached the `probe`, and to prove that each failing request now reaches the `probe` exactly once.

## Launching the Lab

Run this command to start the cluster with the aggressive retry policy already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-02-02
```
