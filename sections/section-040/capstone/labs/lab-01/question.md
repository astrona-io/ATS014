# Question

Solve this question on: `terminal`

Namespace `payments` runs a ledger service with one poisoned replica, and a load generator:

* `ledger-good` — **2 replicas**, healthy. `/delay/<seconds>` sleeps; `/status/<code>` returns that status.
* `ledger-bad` — **1 replica** of nginx returning **503 to every request** while passing its readiness probe.
* `ledger` — one Service on port 8000 in front of **all three** pods
* `fortio` — a load generator. Its pod has containers `fortio` and `istio-proxy`.

Istio is installed, every pod is injected, and there is no `VirtualService` and no `DestinationRule`. Roughly a third of all traffic currently fails.

Deliver a resilient path to this service.

**VirtualService `ledger`, for host `ledger`, with exactly two `http` rules in this order**

1.  **First**, a rule matching method **`POST`**: routes to `ledger` port 8000, `timeout` **`3s`**, and retries **explicitly disabled**. A retried payment is a duplicate payment, and omitting the `retries` block is not the same as disabling it.
2.  **Second**, the catch-all read rule: routes to `ledger` port 8000, `retries` with `attempts` **2**, `perTryTimeout` **`1s`**, `retryOn` **`gateway-error`**, and a `timeout` that is large enough for the whole retry budget to run. Work the budget out rather than guessing.

**DestinationRule `ledger`, for host `ledger`**

3.  `connectionPool` with `tcp.maxConnections` **2** and `http.http1MaxPendingRequests` **2**.
4.  `outlierDetection` with `consecutive5xxErrors` **3**, `interval` **`5s`**, `baseEjectionTime` **`30s`**, and a `maxEjectionPercent` that can actually eject one endpoint out of three.
5.  `loadBalancer.localityLbSetting` with `enabled: true`.

**What the grader checks**

6.  A `GET /status/503` produces **3** requests at the service — the original plus two retries.
7.  A `POST /status/503` produces exactly **1**.
8.  The read rule's `timeout` is at least `(attempts + 1) × perTryTimeout`.
9.  A concurrent `fortio` run produces `503`s carrying the **`UO`** flag, and `upstream_rq_pending_overflow` increases.
10. After driving traffic, the failing endpoint is ejected — `OUTLIER CHECK: FAILED`, or the ejection counters have moved.
11. All three ledger pods are still running with their original replica counts, and the Service selector is unchanged.
