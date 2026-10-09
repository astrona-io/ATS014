---
estimated_duration: 25m
---

# Issue A Sticky Cookie On One Port Lab

A build lab. The clients are browsers, which send no identifying header, so hashing a header would do nothing. The learner makes the sidecar proxy create a session cookie itself (`httpCookie` with a `ttl`), attaches the policy at port level with `portLevelSettings`, and proves that a client with the cookie stays on one pod while a client without it is spread.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-02
```
