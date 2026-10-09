---
estimated_duration: 15m
---

# Create A Gateway API Gateway For A Waiting HTTPRoute Lab

A build lab. In the `starfleet` namespace, an `HTTPRoute` for the `bridge` Service already exists. It names a `Gateway` called `starfleet-gateway`, but that `Gateway` does not exist yet, so no request can reach the `bridge` Service through a gateway.

The learner creates the Gateway API `Gateway`, checks that Istio deployed its proxy in the `starfleet` namespace, and proves that requests for `starfleet.example.com` reach the `bridge` Service through it.

## Launching the Lab

Run this command to start the cluster with the waiting `HTTPRoute` in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03-02
```
