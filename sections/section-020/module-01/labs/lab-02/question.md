---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Two new versions of the `scout` are ready for testing at the same time. The team wants real requests on both, but most traffic must stay on the proven `v1`.

The namespace `starfleet` runs these workloads:

* `scout-v1`, `scout-v2` and `scout-v3`: three versions behind one `scout` Service on port `9080`, **1 replica each**. Each pod has the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `bridge`, `cargo` and `navcom`: the other workloads of the app.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy. Two Istio objects already exist:

* A `DestinationRule` named `scout` with the subsets `v1`, `v2` and `v3`. **It is correct.**
* A `VirtualService` named `scout` that sends every `scout` request to the subset `v1`.

Change the `VirtualService` so that:

1.  The `VirtualService` named `scout` in `starfleet` has **exactly one** `http` rule, with **no** `match`.
2.  That rule's route has three destinations on `scout`: subset **`v1` with weight 60**, subset **`v2` with weight 30** and subset **`v3` with weight 10**.
3.  The `shuttle` pod's sidecar proxy holds those three weights for the `scout` route on port `9080`.
4.  Out of 200 requests sent to `http://scout:9080/reviews/0`, every version answers in roughly its share. The grader accepts 90–150 for `v1`, 36–84 for `v2` and 6–40 for `v3`.
5.  There is exactly one `VirtualService` for `scout`.
6.  The `DestinationRule` named `scout` is **left unchanged**.
7.  Leave the Deployments, their replica counts, their pod labels and the Services unchanged. Do not add or remove workloads.

Each `scout` response contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which version answered.

The grader sends live requests from the `shuttle` pod and reads the `shuttle` proxy's configuration, so the split has to work, not only exist as an object.
