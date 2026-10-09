---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

The `starfleet` team asked for a simple routing rule for the `scout` Service: requests from `jason` go to `scout-v2`, and every other request goes to `scout-v1`. Someone wrote a `VirtualService` and applied it, and `kubectl` accepted it. But every request still lands on a random `scout` version.

The namespace `starfleet` holds the sample application:

* `scout-v1`, `scout-v2` and `scout-v3`: three versions of a backend behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `bridge`, `cargo` and `navcom`: the rest of the application.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy. Two Istio objects already exist:

* A `DestinationRule` named `scout` in `starfleet`, with the subsets `v1`, `v2` and `v3`. **This `DestinationRule` is correct.**
* A `VirtualService` named `scout`. It does not work, and it has **more than one** fault.

Repair the `VirtualService` so that:

1.  **Exactly one** `VirtualService` describes the host `scout.starfleet.svc.cluster.local`, and it routes the requests that `shuttle` sends.
2.  No `VirtualService` uses the short host `scout` in any namespace other than `starfleet`.
3.  All 10 out of 10 requests sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.
4.  All 10 out of 10 requests sent without that header are answered by `scout-v1`.
5.  The `VirtualService` has two rules: first the `jason` rule, then a catch-all rule with no `match`.
6.  `istioctl analyze -A` reports no `IST0101` and no `IST0130` for the `scout` `VirtualService`.
7.  Leave the `DestinationRule`, the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

You may fix the namespace problem in either of two ways: put the `VirtualService` in `starfleet`, or keep it where it is and write the full name `scout.starfleet.svc.cluster.local` everywhere it names the host.

Each `scout` response contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which version answered.

The grader sends real requests from the `shuttle` pod, so the `VirtualService` has to work, not only exist.
