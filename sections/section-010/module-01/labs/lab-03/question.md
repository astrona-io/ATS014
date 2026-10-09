---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The `starfleet` team reports trouble: every request that the user `jason` sends to the `scout` Service fails with `503`. Requests from everyone else still get an answer.

The namespace `starfleet` holds the sample application:

* `scout-v1`, `scout-v2` and `scout-v3`: three versions of a backend behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `bridge`, `cargo` and `navcom`: the rest of the application.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy. Two Istio objects already exist:

* A `VirtualService` named `scout`. It sends requests with the header `end-user: jason` to the subset `v2`, and every other request to the subset `v1`. **This `VirtualService` is correct.**
* A `DestinationRule` named `scout`, which defines the subsets. Something in it is wrong.

Fix the problem so that:

1.  The `DestinationRule` named `scout` in `starfleet` defines **exactly three subsets**: `v1`, `v2` and `v3`.
2.  Each subset selects pods by the `version` label, with the value equal to its own name (`v1` selects `version: v1`, and so on).
3.  Every subset has at least one healthy endpoint in the proxy of the `shuttle` pod.
4.  All 10 out of 10 requests sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.
5.  All 10 out of 10 requests sent without that header are answered by `scout-v1`.
6.  The `VirtualService` named `scout` is **left unchanged**.
7.  Leave the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

Each `scout` response contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which version answered.

The grader sends real requests from the `shuttle` pod and reads the endpoints in its proxy, so the fix has to work, not only exist.
