---
estimated_duration: 15m
---

# Move A Timeout Off A Fault Rule Lab

A troubleshooting lab. In the `starfleet` namespace, a delay fault makes `navcom` answer 3 seconds late. Someone put a 1-second timeout on the same `VirtualService` rule as the delay fault, so the timeout never fires: a rule with a `fault` ignores its own `timeout`.

The task is to move the timeout to the `jason` rule of the `scout` `VirtualService`, and to prove that the `shuttle` sidecar proxy now returns `504` with the response flag `UT` after one second.

## Launching the Lab

Run this command to start the cluster with the problem already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-01-02
```
