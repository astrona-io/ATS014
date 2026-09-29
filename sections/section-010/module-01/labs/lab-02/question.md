# Question

Solve this question on: `terminal`

Namespace `routing-demo` runs two versions of one application behind a single Service:

* `notification-service-v1` — pods labelled `version: v1`, answers `["EMAIL"]`
* `notification-service-v2` — pods labelled `version: v2`, answers `["EMAIL","SMS"]`
* `notification-service` — one Service on port 80 selecting on `app` only, so both versions receive traffic
* `tester` — a client pod with `curl`

Istio is installed and every pod in `routing-demo` is injected. There is no `VirtualService` and no `DestinationRule`.

The team is moving an API without redeploying it. The application still serves everything at `/notify` and knows nothing about the paths clients actually use.

Configure host `notification-service` in namespace `routing-demo` so that:

1.  A `DestinationRule` named `notification-service` defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification-service` answers any request whose URI starts with **`/legacy`** with a **301 redirect to `/notify`**. Nothing may be forwarded to a pod for these requests.
3.  Requests whose URI starts with **`/beta`** are **rewritten** so the matched prefix becomes **`/`** — `/beta/notify` must reach the application as `/notify` — and are routed to subset **`v2`**.
4.  Every response leaving this service carries the response header **`x-served-by: notification`**.
5.  The request header **`x-internal-token`** is **removed** before any request is forwarded upstream.
6.  Cross-origin requests from exactly **`https://shop.example.com`** are permitted, for methods **`GET`** and **`POST`**.
7.  **Every other request** goes to subset **`v1`**.
8.  Leave the Deployments and the Service unchanged. Do not add a third Deployment, and do not change the Service selector.

Two notes that will save you time:

* A rule with a `redirect` cannot also have a `route`. They are alternatives.
* A working rewrite is **not** visible in any access log — Istio's log format reports the original path. The grader checks the compiled route for it, and so should you: `istioctl proxy-config routes deploy/tester -n routing-demo -o json`.

The grader sends live traffic from the `tester` pod and reads the responses and the proxy's own configuration, so the rules have to work — not merely exist.
