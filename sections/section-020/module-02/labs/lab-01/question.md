# Question

Solve this question on: `terminal`

Namespace `mirror-demo` runs two versions of one application behind a single Service:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]` — the **stable** version
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]` — the **release candidate**
* `notification-service` — one Service on port 80 selecting on `app` only
* `tester` — a client pod with `curl`

Istio is installed, every pod is injected, and there is no `VirtualService` and no `DestinationRule`.

Astronaut, the release candidate is a test ship: you want production traffic exercising it without a single user seeing its output.

1.  A `DestinationRule` named `notification-service` defining exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification` for host `notification-service` that routes **100% of caller traffic to subset `v1`**.
3.  The same rule must **mirror** those requests to subset **`v2`**.
4.  Set `mirrorPercentage` explicitly to **100**.
5.  Every caller response must come from `v1`. The grader sends 30 requests and fails if any of them returns the `v2` body — a mirrored response must never reach the caller.
6.  The shadow must actually receive the copies. The grader counts requests arriving at `v2` carrying the rewritten `-shadow` authority, so a mirror that silently does nothing fails even though the caller is perfectly happy.
7.  Do not scale either Deployment, do not change the Service selector, and do not add a third Deployment.

Hint: the caller's output cannot tell you whether the mirror works. Find the evidence on the receiving side.
