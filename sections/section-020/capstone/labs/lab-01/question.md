# Question

Solve this question on: `terminal`

Namespace `checkout` holds a canary in progress and a shadow deployment that has never received traffic:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]` — **stable**, 1 replica
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]` — **canary**, 1 replica
* `notification-service` — one Service on port 80 selecting on `app` only
* `notification-shadow` — a **separate** Deployment and Service on port 80, the shadow target, 1 replica
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no `VirtualService` and no `DestinationRule`.

Astronaut, your mission: one flight plan that runs a test flight and a listening test ship at the same time. Deliver the following on one `VirtualService` named `notification` for host `notification-service`.

**Subsets**

1.  A `DestinationRule` named `notification-service` defining exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

**Rule 1 — internal testers**

2.  The **first** `http` rule matches the header **`x-internal: true`** and sends those requests to subset **`v2`**, unconditionally. Internal testers always get the canary, whatever the percentage is.

**Rule 2 — the canary split, plus the shadow**

3.  The **second** `http` rule is the catch-all: no `match` block.
4.  It splits caller traffic **80% to `v1`** and **20% to `v2`** in a single route block.
5.  The **same rule** mirrors its requests to the separate host **`notification-shadow`**, with `mirrorPercentage` set explicitly to **100**.
6.  The mirror must be a mirror, not a third weighted destination: no caller response may ever come from `notification-shadow`.

**What the grader checks**

7.  A request with `x-internal: true` reaches `v2` every time — it is not part of the split.
8.  Over 200 ordinary requests, `v1`'s share is in a band around 80%. An all-v1 or all-v2 result fails.
9.  `notification-shadow` receives a copy of essentially every ordinary request, identifiable by the rewritten `-shadow` authority in its proxy access log.
10. No Deployment's replica count has changed — all four still run exactly 1 replica. Traffic share is a weight, not a pod count.
11. The `notification-service` Service selector still selects on `app` only, and no Deployment was added or removed.
