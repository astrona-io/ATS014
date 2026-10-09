# Question

Solve this question on: `terminal`

The team behind `notification-service` wants to release `v2` as a canary: a small share of all requests goes to `v2` first, while internal testers always use `v2`.

Namespace `shifting-demo` runs two versions of one application behind a single Service:

* `notification-service-v1`: pods labelled `version: v1`, answers `["EMAIL"]`, **1 replica**
* `notification-service-v2`: pods labelled `version: v2`, answers `["EMAIL","SMS"]`, **1 replica**
* `notification-service`: one Service on port 80 that selects pods on the `app` label only
* `tester`: a client pod with `curl`

Istio is installed, every pod has its sidecar proxy, and there is no `VirtualService` and no `DestinationRule`. Requests go to `http://notification-service/notify` with the `POST` method.

Deliver the following:

1.  A `DestinationRule` named `notification-service` with exactly two subsets, **`v1`** and **`v2`**, each selecting pods on the **`version`** label.
2.  A `VirtualService` named `notification` for the host `notification-service`, with **two** `http` rules in this order:
    *   **First**, a rule that matches the header **`x-internal: true`** and sends those requests to subset **`v2`**. Internal testers always get the new version, whatever the canary share is.
    *   **Second**, a weighted rule with no `match` that splits all other requests **70% to `v1`** and **30% to `v2`**.
3.  The weighted rule must be a single route list with two destinations that carry `weight: 70` and `weight: 30`.
4.  A request with the header `x-internal: true` must reach `v2` every time. It must not be part of the split.
5.  Ordinary requests must reach **both** versions, in roughly the configured shares. The grader sends 200 requests and accepts 55–85% for `v1`, so an all-`v1` or all-`v2` result fails.
6.  Do **not** change the replica count of either Deployment. The traffic share is set by a weight, not by a pod count, and the grader checks that both Deployments still run exactly 1 replica.
7.  Do not change the Service selector, and do not add a third Deployment.

The grader also checks that the `tester` pod's sidecar proxy holds the weighted clusters, so the split has to reach the proxy, not only exist as an object.
