---
estimated_duration: 30m
---

# Configure And Prove A Connection Pool Circuit Breaker Lab

In this lab you set a connection pool on a client's traffic to a backend. The limit caps how much work the client's sidecar proxy may have open to the backend at the same time. Then you prove that the limit is real: the same number of requests succeeds when sent one by one and is partly refused when sent at the same time.

## Launching the Lab

Run this command to start the `kind` Kubernetes cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-02
```
