# Question

Solve this question on: `terminal`

A canary release is in progress, and a shadow copy of the service is ready but has never received traffic. The team wants both at once: a small share of real users on the canary, and a full copy of the same traffic on the shadow.

The namespace `checkout` runs:

* `notification-service-v1`: pods labelled `version: v1`, returns `["EMAIL"]`. This is the **stable** version, 1 replica.
* `notification-service-v2`: pods labelled `version: v2`, returns `["EMAIL","SMS"]`. This is the **canary**, 1 replica.
* `notification-service`: one Service on port `80` that selects on the `app` label only.
* `notification-shadow`: a **separate** Deployment and Service on port `80`. This is the shadow target, 1 replica.
* `tester`: a client pod with `curl`. Send requests with `curl -X POST http://notification-service/notify`.

Istio is installed and every pod has a sidecar proxy. There is no `VirtualService` and no `DestinationRule`.

Build everything on one `VirtualService` named `notification` for the host `notification-service`, with exactly two `http` rules.

**Subsets**

1.  A `DestinationRule` named `notification-service` that defines two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

**Rule 1: internal testers**

2.  The **first** `http` rule matches the header **`x-internal: true`** (exact match) and sends those requests to subset **`v2`**. Internal testers always get the canary, whatever the weights are.

**Rule 2: the canary split and the mirror**

3.  The **second** `http` rule is the catch-all rule: it has no `match` block.
4.  It splits client requests **80% to `v1`** and **20% to `v2`** in a single `route` list.
5.  The **same rule** mirrors its requests to the separate host **`notification-shadow`**, with `mirrorPercentage` set explicitly to **100**.
6.  The mirror must be a mirror, not a third weighted destination: `notification-shadow` must not appear in any `route`, so no client response ever comes from it.

**What the grader checks**

7.  The proxy of the `tester` pod holds both `weightedClusters` and `requestMirrorPolicies`.
8.  Five requests with `x-internal: true` all reach `v2`. Those requests are not part of the split.
9.  Over 200 ordinary requests, the share of `v1` is between 65% and 92%. An all-v1 or all-v2 result fails.
10. `notification-shadow` receives a copy of almost every ordinary request: the grader counts at least 150 new lines for the 200 requests in the access log of the `notification-shadow` sidecar proxy.
11. No replica count has changed: all four Deployments still run exactly 1 replica. Traffic share is a weight, not a pod count.
12. The `notification-service` Service still selects on `app` only, and no Deployment was added or removed.
