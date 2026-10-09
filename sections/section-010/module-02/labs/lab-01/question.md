# Question

Solve this question on: `terminal`

The platform team wants the proxies in one namespace to know only about the hosts that namespace actually calls. Istio 1.30.5 is installed, and three namespaces have sidecar injection switched on:

* `sidecar-demo`: a `tester` client pod with `curl`, and a `local-backend` Service on port `8000`
* `sidecar-other`: an `httpbin` Service on port `8000`
* `sidecar-third`: an `httpbin` Service on port `8000`

There is no `Sidecar` resource anywhere, so every sidecar proxy holds configuration for every Service in the mesh. From `tester`, all three backends answer.

The mesh runs with `outboundTrafficPolicy: REGISTRY_ONLY`. A request for a host that is not in the proxy's configuration therefore fails, instead of leaving through a passthrough.

1.  Create a `Sidecar` resource named **`default`** in the namespace **`sidecar-demo`** that applies to **every workload in that namespace**. Do not use a `workloadSelector`.
2.  Limit its `egress` hosts to exactly three things: the proxy's **own namespace**, **`istio-system`**, and **`sidecar-other`**.
3.  `sidecar-third` must **not** be in the `tester` proxy's configuration, and must not be reachable from `tester`.
4.  `sidecar-other` must still be reachable from `tester`: `http://httpbin.sidecar-other:8000/get` must return `HTTP 200`.
5.  `local-backend` in the proxy's own namespace must still be reachable.
6.  The `tester` proxy's cluster list must be clearly smaller than before.
7.  Leave the Deployments, Services and namespaces unchanged. Do not delete `sidecar-third` or its workload: the `Sidecar` must stop the traffic, not the removal of the target.

The grader reads the `tester` proxy's own configuration *and* sends live requests, so both the smaller configuration and the reachability must be real.
