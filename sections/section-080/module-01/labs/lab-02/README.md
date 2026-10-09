---
estimated_duration: 25m
---

# Fix An Egress Route That Skips The Gateway Lab

This graded lab is a troubleshooting task. Requests from the `starfleet` namespace to an outside endpoint, the relay, should leave the cluster through the egress gateway, so that one access log records every one of them. The route is written and the relay answers, but the egress gateway's access log stays empty.

Your task is to find out why with the access logs and the proxy configuration, fix every fault, and prove that the requests really pass through the egress gateway. This lab needs no outbound internet access.

## Running the lab

Start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-01-02
```
