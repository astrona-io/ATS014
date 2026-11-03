---
estimated_duration: 15m
---

# Build A DestinationRule For A STRICT Destination Lab

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

A build lab. In the `starfleet` namespace, a `PeerAuthentication` makes the `probe` pods accept only mutual TLS (mTLS) connections, and a `VirtualService` already sends requests to two subsets, `v1` and `v2`, that do not exist yet. The learner writes the `probe` `DestinationRule` so that mesh clients keep working: the subsets, the client TLS mode, and a load balancer that only subset `v2` overrides.

The grader reads the `DestinationRule`, reads the `shuttle` pod's proxy configuration for both subset clusters, and sends live requests from the `shuttle` pod. It also sends one request from the `drifter` pod in `outpost`, which has no sidecar proxy, and expects it to stay refused.

The lab ships three helper scripts: `count-pods.sh`, `status-codes.sh` and `drifter-call.sh`. Learners list them with `astrona res`.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-02-01
```
