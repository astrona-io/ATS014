---
estimated_duration: 30m
---

# Combine TLS Settings With Load Balancing Capstone Lab

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

The second integration lab for the "Defining Traffic Policies With Destination Rules" section. It combines the client TLS mode from the TLS module with the load balancer policy from the load balancer module in one `DestinationRule`: host-level mTLS and session affinity, and a different load balancer for one subset.

The `probe` pods accept only mTLS because of a `PeerAuthentication`, so the TLS part has to be right for any request to succeed. The load balancer part is then proved by which pods answer. A subset that sets only a `loadBalancer` still inherits the host's `tls`, and the capstone checks that the combination works for both subsets.

There is no step-by-step guide on the task page. The learner works from the specification first.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/capstone/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/capstone/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-030-02
```
