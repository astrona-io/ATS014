# Question

Solve this question on: `terminal`

One replica of the payment ledger has gone bad, and the service must keep working for its callers while that replica stays in place.

Namespace `payments` runs a ledger service with one broken replica, and a load generator:

* `ledger-good`: **2 replicas**, healthy. `/delay/<seconds>` waits that many seconds; `/status/<code>` returns that status code.
* `ledger-bad`: **1 replica** of nginx that returns **503 to every request** while it still passes its readiness probe.
* `ledger`: one Service on port 8000 in front of **all three** pods.
* `fortio`: a load generator. Its pod has the containers `fortio` and `istio-proxy`.

Istio is installed, every pod has a sidecar proxy, and there is no `VirtualService` and no `DestinationRule`. About a third of all requests fail today.

Configure a resilient path to this service.

**VirtualService `ledger`, for host `ledger`, with exactly two `http` rules in this order**

1.  **First**, a rule that matches the method **`POST`**: it routes to `ledger` port 8000, has a `timeout` of **`3s`**, and has retries **explicitly disabled**. A retried payment is a duplicate payment, and leaving out the `retries` block is not the same as disabling retries.
2.  **Second**, the catch-all rule for reads: it routes to `ledger` port 8000, has `retries` with `attempts` **2**, `perTryTimeout` **`1s`** and `retryOn` **`gateway-error`**, and a `timeout` that is long enough for all the retries to run. Calculate this time budget; do not guess it.

**DestinationRule `ledger`, for host `ledger`**

3.  `connectionPool` with `tcp.maxConnections` **2** and `http.http1MaxPendingRequests` **2**.
4.  `outlierDetection` with `consecutive5xxErrors` **3**, `interval` **`5s`**, `baseEjectionTime` **`30s`**, and a `maxEjectionPercent` that can really eject one endpoint out of three.
5.  `loadBalancer.localityLbSetting` with `enabled: true`.

**What the grader checks**

6.  A `GET /status/503` reaches the service **3** times: the original request plus two retries.
7.  A `POST /status/503` reaches the service exactly **1** time.
8.  The `timeout` of the read rule is at least `(attempts + 1) × perTryTimeout`.
9.  A concurrent `fortio` run produces `503` responses with the **`UO`** response flag (upstream overflow), and the `upstream_rq_pending_overflow` counter increases.
10. After the grader sends traffic, the failing endpoint is ejected: `OUTLIER CHECK: FAILED`, or the ejection counters have increased.
11. All three ledger Deployments still run with their original replica counts, and the Service selector is unchanged.
