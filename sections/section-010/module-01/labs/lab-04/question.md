---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, mission control asked for a simple flight plan for the scout beacon: signals from `jason` fly to `scout-v2`, everyone else flies to `scout-v1`. Someone wrote it and applied it. `kubectl` accepted it. But every signal still lands on a random scout ship.

The planet `starfleet` holds the Starfleet:

* `scout-v1`, `scout-v2` and `scout-v3`: three ship classes behind one `scout` Service on port `9080`. Each pod carries the labels `app: scout` and `version: v1`, `v2` or `v3`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `bridge`, `cargo` and `navcom`: the rest of the fleet.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. Two Istio objects already exist:

* A `DestinationRule` named `scout` in `starfleet`, with the subsets `v1`, `v2` and `v3`. **These docking instructions are correct.**
* A `VirtualService` named `scout` (the flight plan). It does not work, and there is **more than one** fault in it.

Repair the flight plan so that:

1.  **Exactly one** `VirtualService` describes the scout beacon `scout.starfleet.svc.cluster.local`, and it routes the signals the `shuttle` sends.
2.  No `VirtualService` uses the short host `scout` on any planet other than `starfleet`.
3.  All 10 out of 10 signals sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.
4.  All 10 out of 10 signals sent without that header are answered by `scout-v1`.
5.  The flight plan has two rules: first the jason rule, then a catch-all rule with no `match`.
6.  `istioctl analyze -A` reports no `IST0101` and no `IST0130` for the scout flight plan.
7.  Leave the `DestinationRule`, the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

You may fix the planet in either of two ways: put the flight plan in `starfleet`, or keep it where it is and write the full name `scout.starfleet.svc.cluster.local` everywhere it names the beacon.

Each `scout` answer contains the name of the pod that sent it (`"podname": "scout-v2-..."`), so you can see which ship class answered.

The grader sends live signals from the `shuttle` pod, so the flight plan has to work, not merely exist.
