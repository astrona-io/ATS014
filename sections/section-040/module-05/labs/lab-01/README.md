---
estimated_duration: 15m
---

# Set Connection Timeout And Keepalive On A Host

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

In this lab, the `shuttle` pod in namespace `starfleet` calls the `probe` Service, and nothing limits how long its sidecar proxy waits for a connection, how long a connection may idle or live, or whether a dead connection is noticed.

Your job is to write one `DestinationRule` that sets the connect timeout, the idle timeout, the maximum connection duration and TCP keepalive for the `probe` host, and to prove the settings from the cluster JSON of the proxy and with live requests.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-05/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-05/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-05-01
```
