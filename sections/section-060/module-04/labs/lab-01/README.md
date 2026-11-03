---
estimated_duration: 30m
---

# Secure An Ingress Gateway With HTTPS And A Redirect

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run against a cluster yet.

This is a build lab. The ingress gateway of the cluster serves no HTTPS yet. You receive a certificate and a private key for `probe.example.com`, turn them into a secret that the gateway can load, and write a `Gateway` and a `VirtualService` that serve `probe.example.com` over HTTPS and redirect plain HTTP to HTTPS.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-04/labs/lab-01
```

The start script writes the certificate and the key to `/tmp/probe-example.crt` and `/tmp/probe-example.key` on your machine.

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-04/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-04-01
```
