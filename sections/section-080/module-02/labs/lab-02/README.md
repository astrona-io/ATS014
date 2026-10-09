---
estimated_duration: 25m
---

# Fix Mutual TLS Origination At The Egress Gateway Lab

A troubleshooting lab. Requests from the `starfleet` namespace to a partner server should leave through the egress gateway, and the egress gateway should present a client certificate to the partner in a mutual TLS handshake. The route is written and the client certificate was delivered as a `Secret`, but every request fails.

Your job is to find out why with the access logs, the egress gateway's certificates (`istioctl proxy-config secret`) and the `istiod` log, fix every fault, and prove that the partner server accepts the egress gateway's certificate. This lab needs no outbound internet access.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-02-02
```
