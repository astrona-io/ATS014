# Question

Solve this question on: `terminal`

Astronaut, your mission: steer the signals on one planet. Namespace `routing-demo` runs two versions of one application behind a single Service:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]`
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]`
* `notification-service` — one Service on port 80 selecting on `app` only, so both versions receive traffic
* `tester` — a client pod with `curl`

Istio is installed and every pod in `routing-demo` is injected. There is no `VirtualService` and no `DestinationRule`.

Configure routing for host `notification-service` in namespace `routing-demo` so that:

1.  A `DestinationRule` named `notification-service` defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification-service` routes requests carrying the header **`testing: true`** to subset **`v2`**.
3.  The same `VirtualService` routes requests whose URI starts with **`/notify/beta`** to subset **`v2`**.
4.  The same `VirtualService` routes requests carrying the query parameter **`version=2`** to subset **`v2`**.
5.  **Every other request** goes to subset **`v1`**. A request with no header, no matching path and no query parameter must reach `v1` every time — not sometimes.
6.  The three specific rules must each be reachable. A default route that swallows traffic before them is a failure, even though it produces no error.
7.  Leave the Deployments and the Service unchanged. Do not add a third Deployment, and do not change the Service selector.

The grader sends live traffic from the `tester` pod and reads the responses, so the rules have to work — not merely exist.
