---
estimated_duration: 30m
---

# Originate TLS To A TLS-Only External Service

The endpoint in this lab accepts **only** TLS (Transport Layer Security) connections, and the client calls it over plain `http://`. The client's sidecar proxy must originate TLS, that is, open the TLS connection itself on the way out. The endpoint reports which scheme it received, so there is no guessing whether it worked.

This lab needs **no outbound internet access**: the TLS endpoint runs inside the cluster, outside the mesh's service registry.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-02
```
