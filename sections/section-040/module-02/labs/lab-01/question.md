# Question

Solve this question on: `terminal`

A client sends requests to a backend without any limit. When the backend gets slow, the requests pile up in the client. Configure a connection pool so that the client's sidecar proxy refuses work it cannot send at once, instead of queueing it.

The namespace `circuit-demo` runs one backend and one load generator:

* `notification-service`: a Service on port 80, backed by one pod.
* `fortio`: a load generator that can send many requests at the same time. Its pod has two containers, `fortio` and `istio-proxy`, so `kubectl exec` needs `-c fortio` or `-c istio-proxy`.

Istio is installed, both pods have a sidecar proxy, and there is no `DestinationRule`. The number of requests that may be open at the same time has no limit.

1.  Create a `DestinationRule` named `notification-service` for the host `notification-service`.
2.  In its `trafficPolicy.connectionPool`, set:
    *   `tcp.maxConnections` to **1**
    *   `http.http1MaxPendingRequests` to **1**
    *   `http.maxRequestsPerConnection` to **1**
3.  Do **not** create a `VirtualService`. A retry policy would hide the refusals this task is about, and the grader checks that none exists in `circuit-demo`.

**What the grader checks**

4.  The three settings are present in the object with those exact values.
5.  The `fortio` proxy's cluster configuration shows `maxConnections: 1` and `maxPendingRequests: 1`, so the limits really reached the sidecar proxy.
6.  A **sequential** run (`fortio load -c 1 -n 20`) still succeeds completely (at least 19 of 20 requests get a `200`). The limit is on requests at the same time, not on the number of requests, so this run must not fail.
7.  A **concurrent** run (`fortio load -c 5 -n 50`) gets some `503` responses.
8.  Those refusals carry the **`UO`** response flag in the `fortio` proxy's access log.
9.  The `upstream_rq_pending_overflow` counter for the `notification-service` cluster goes up during the concurrent run.
10. The backend's own proxy logged **no** `503` responses, because the refused requests never reached it.
