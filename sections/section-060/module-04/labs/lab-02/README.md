---
estimated_duration: 30m
---

# Fix A Secret In The Wrong Namespace And A Passthrough Mismatch

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run against a cluster yet.

This is a troubleshooting lab. In the `starfleet` namespace, a `Gateway` serves two hosts and both fail over HTTPS. One host should be decrypted by the gateway, and its certificate is in the wrong place. The other host should pass encrypted traffic through to the `archive`, and its route is the wrong kind.

Your job is to find both causes, fix them without changing the purpose of either server, and prove it with real requests.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-04/labs/lab-02
```

The start script writes a certificate and a key for `starfleet.example.com` to `/tmp/starfleet-example.crt` and `/tmp/starfleet-example.key` on your machine.

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-04/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-04-02
```
