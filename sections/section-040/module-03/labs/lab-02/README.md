---
estimated_duration: 3m
---

# Combine A Connection Pool And Outlier Detection Lab

This graded lab checks that you can build a circuit breaker for one Service and prove that both of its halves work on live requests.

## What you will practise

A **circuit breaker** in Istio is two settings in one `DestinationRule`. A **connection pool** limits how many connections and waiting requests a client's sidecar proxy may have open to a host, and refuses the extra requests with `503 UO`. **Outlier detection** makes the client's proxy stop sending requests to an endpoint that keeps failing.

In the namespace `starfleet`, the `probe` Service has three pods, and one of them answers every request with `503` while Kubernetes reports it as ready. Nothing limits how many requests a client may send to the `probe` at the same time.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm.
- The namespace `starfleet` with `probe-v1`, `probe-v2`, the broken `probe-broken`, the `shuttle` client pod and the `fortio` load generator.
- No `DestinationRule` for the `probe`.

## Running the lab

Start the cluster with the broken pod already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-03-02
```
