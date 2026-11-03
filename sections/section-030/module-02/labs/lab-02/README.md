---
estimated_duration: 20m
---

# Fix A DISABLE Rule And A Subset Override Lab

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

A troubleshooting lab. In the `starfleet` namespace, a `PeerAuthentication` makes the `probe` pods accept only mutual TLS (mTLS) connections. The `probe` `DestinationRule` has two mistakes. Its top-level `tls.mode` is `DISABLE`, so requests from the `shuttle` pod fail. And subset `v2` sets its own `loadBalancer`, which silently replaces the host's `consistentHash`, so subset `v2` is no longer sticky.

The learner finds the first mistake in the `DestinationRule` and the proxy's TLS transport socket, fixes it, and then finds the second one by checking which pods answer a repeated `x-user` value and the proxy's `lbPolicy` for each subset cluster.

The lab ships three helper scripts (`count-pods.sh`, `status-codes.sh`, `drifter-call.sh`) and `probe-destinationrule.yaml`, the starting `DestinationRule` that `bootstrap/03-seed-fault.sh` applies. Learners list them with `astrona res`.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-030-02-02
```
