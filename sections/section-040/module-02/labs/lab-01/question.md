# Question

Solve this question on: `terminal`

Namespace `circuit-demo` runs one backend and one load generator:

* `notification-service` — a Service on port 80, backed by one pod
* `fortio` — a load generator. Its pod has two containers, `fortio` and `istio-proxy`, so `kubectl exec` needs `-c fortio` or `-c istio-proxy`.

Istio is installed, both pods are injected, and there is no `DestinationRule`. Concurrency is currently unbounded.

The caller must refuse work it cannot do promptly rather than queueing it.

1.  Create a `DestinationRule` named `notification-service` for host `notification-service`.
2.  In its `trafficPolicy.connectionPool`, set:
    *   `tcp.maxConnections` to **1**
    *   `http.http1MaxPendingRequests` to **1**
    *   `http.maxRequestsPerConnection` to **1**
3.  Do **not** create a `VirtualService`. A retry policy would hide the rejections this task is about, and the grader checks that none is present.

**What the grader checks**

4.  The three settings are present in the object with those exact values.
5.  The `fortio` proxy's cluster config shows `maxConnections: 1` and `maxPendingRequests: 1` — the limits really reached the sidecar.
6.  A **sequential** run (`fortio load -c 1 -n 20`) still succeeds completely. The limit is on concurrency, not on the number of requests, so this must not fail.
7.  A **concurrent** run (`fortio load -c 5 -n 50`) produces some `503`s.
8.  Those rejections carry the **`UO`** response flag in the `fortio` proxy's access log.
9.  The `upstream_rq_pending_overflow` counter for the `notification-service` cluster is greater than zero.
10. The backend's own proxy logged **no** 503s — the rejected requests never reached it.
