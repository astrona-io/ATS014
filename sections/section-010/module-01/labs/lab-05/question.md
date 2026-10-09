---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The `starfleet` team set up routing for the `probe` echo server: requests that carry the header `x-mission: test` go to `probe-v2`, and every other request goes to `probe-v1`. The `VirtualService` and the `DestinationRule` are both correct. But requests still reach both `probe` versions, as if no `VirtualService` existed.

The namespace `starfleet` holds:

* `probe-v1` and `probe-v2`: two versions of an echo server behind one `probe` Service on port `8000` (the pods listen on `8080`). Each pod carries the labels `app: probe` and `version: v1` or `v2`. The path `/hostname` answers with the name of the pod that served the request.
* `shuttle`: a client pod with `curl`. Send your test requests from here.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy. Two Istio objects already exist, and **both are correct**:

* A `DestinationRule` named `probe` with the subsets `v1` and `v2`.
* A `VirtualService` named `probe` with two `http` rules: `x-mission: test` to subset `v2`, then a catch-all to subset `v1`.

Restore HTTP routing so that:

1.  Port `8000` of the `probe` Service is declared as HTTP: its `name` is `http` or starts with `http-`, or its `appProtocol` is `http`.
2.  The port numbers (`8000` to `8080`) and the Service selector stay unchanged.
3.  `probe` appears again in the route table of the `shuttle` proxy for port `8000` (`istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000`).
4.  All 10 out of 10 requests sent to `http://probe:8000/hostname` with the header `x-mission: test` are answered by `probe-v2`.
5.  All 10 out of 10 requests sent without that header are answered by `probe-v1`.
6.  The `VirtualService` keeps its `http` rules unchanged. Do not rewrite it as a `tcp` rule.
7.  Leave the `DestinationRule`, the Deployments and their pod labels unchanged. Do not add or remove workloads.

The grader sends real requests from the `shuttle` pod, so the routing has to work, not only look right.
