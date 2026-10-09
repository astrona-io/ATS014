---
estimated_duration: 15m
---

# Retry Only One Status Code Lab

A build lab. In the `starfleet` namespace, the `probe` `VirtualService` retries every 5xx three times, including the probe's own `500` errors, which fail the same way on every try.

The task is to narrow the retry policy to the status code `503`, with two retries of at most one second each and a route timeout that fits every try, and to prove it by counting the requests in the probe's access log.

## Launching the Lab

Run this command to start the cluster with the starting policy in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-01-03
```
