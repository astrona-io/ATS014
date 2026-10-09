---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, a fellow astronaut reports trouble. On the planet `starfleet`, every signal that `jason` sends to the scout beacon fails with `503`. Everyone else still gets an answer.

The planet `starfleet` holds the Starfleet:

* `scout-v1`, `scout-v2` and `scout-v3`: three ship classes behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `bridge`, `cargo` and `navcom`: the rest of the fleet.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. Two Istio objects already exist:

* A `VirtualService` named `scout` (the flight plan). It sends signals with the header `end-user: jason` to the subset `v2`, and every other signal to the subset `v1`. **This flight plan is correct.**
* A `DestinationRule` named `scout` (the docking instructions). Something in it is wrong.

Fix the problem so that:

1.  The `DestinationRule` named `scout` in `starfleet` defines **exactly three subsets**: `v1`, `v2` and `v3`.
2.  Each subset selects pods by the `version` label, with the value equal to its own name (`v1` selects `version: v1`, and so on).
3.  Every subset has at least one healthy endpoint in the `shuttle`'s proxy.
4.  All 10 out of 10 signals sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.
5.  All 10 out of 10 signals sent without that header are answered by `scout-v1`.
6.  The `VirtualService` named `scout` is **left unchanged**.
7.  Leave the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

Each `scout` answer contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which ship class answered.

The grader sends live signals from the `shuttle` pod and reads the shuttle's proxy, so the fix has to work, not merely exist.
