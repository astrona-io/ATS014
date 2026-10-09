---
estimated_duration: 30m
---

# Set Timeouts And Retries Per HTTP Method Lab

A build lab. In the `resilience-demo` namespace, the task is to write one `VirtualService` for `httpbin` with two rules: a `POST` rule with a timeout and retries switched off (`attempts: 0`), and a catch-all read rule that retries on `gateway-error` with a timeout large enough for every try. The grader then counts, in the server's access log, how many requests really reached it.

This lab uses its own small app (`httpbin` and a `tester` client), not the Starfleet.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-01
```
