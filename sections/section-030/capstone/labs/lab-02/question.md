# Question

Solve this question on: `terminal`

The `probe` service in the `starfleet` namespace accepts only mutual TLS (mTLS) connections. Write the `DestinationRule` that lets mesh clients reach it, keeps each session on one `v1` pod, and spreads requests over the pods of `v2`.

The `starfleet` namespace runs:

* `probe-v1` (3 pods, label `version: v1`) and `probe-v2` (2 pods, label `version: v2`), all labelled `app: probe`, behind one Service `probe` on port `8000`. The path `/hostname` returns the name of the pod that served the request.
* `shuttle`, a client pod with `curl` and a sidecar proxy.
* A `PeerAuthentication` named `probe` with mode `STRICT` for the pods labelled `app: probe`.
* A `VirtualService` named `probe`: requests with the header `x-canary: true` go to subset `v2`, all other requests go to subset `v1`.

The namespace `outpost` runs `drifter`, a client pod with no sidecar proxy.

No `DestinationRule` exists. Create a `DestinationRule` named `probe` in `starfleet` so that:

1.  Its host is `probe`, and it defines the subsets `v1` (pods labelled `version: v1`) and `v2` (pods labelled `version: v2`).
2.  The host-level `trafficPolicy.tls.mode` is `ISTIO_MUTUAL`, and the `DestinationRule` has no `DISABLE` anywhere.
3.  The host-level `trafficPolicy.loadBalancer` is a `consistentHash` on the header `x-session-id`.
4.  Subset `v2` has its own `loadBalancer.simple: ROUND_ROBIN`. No other `simple` setting exists in the `DestinationRule`, and subset `v1` sets no `trafficPolicy`.
5.  The `shuttle` pod's proxy holds a TLS transport socket for both subset clusters, the `lbPolicy` `RING_HASH` for the `v1` cluster, and no `RING_HASH` for the `v2` cluster.
6.  Eight requests with the header `x-session-id: s1` return status `200` and are answered by **one** `probe-v1` pod. Eight requests with `x-session-id: s1` and `x-canary: true` return status `200` and reach **both** `probe-v2` pods.
7.  The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

The grader reads the `DestinationRule`, reads the `shuttle` pod's proxy configuration, and sends live requests, so the connections have to really work.

The lab ships three files in its `resources` folder. `astrona res` lists them. `count-pods.sh` counts which probe pod answers, `status-codes.sh` counts the status codes, and `drifter-call.sh` sends one request from the `drifter`.
