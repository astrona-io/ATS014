# Question

Solve this question on: `terminal`

The `probe` pods in the `starfleet` namespace accept only mutual TLS (mTLS) connections, and requests from the `shuttle` pod fail. The `shuttle` calls `http://probe:8000/hostname` and must get an answer again, from the right version of the `probe`.

The `starfleet` namespace runs:

* `probe-v1` (3 pods, label `version: v1`) and `probe-v2` (1 pod, label `version: v2`), all labelled `app: probe`, behind one Service `probe` on port `8000`. The path `/hostname` returns the name of the pod that served the request.
* `shuttle`, a client pod with `curl` and a sidecar proxy.
* A `PeerAuthentication` named `probe` with mode `STRICT` for the pods labelled `app: probe`.
* A `VirtualService` named `probe`: requests with the header `x-canary: true` go to subset `v2`, all other requests go to subset `v1`.

The namespace `outpost` runs `drifter`, a client pod with no sidecar proxy.

No `DestinationRule` exists, so the two subsets are not defined. Create a `DestinationRule` named `probe` in `starfleet` so that:

1.  Its host is `probe`, and it defines the subsets `v1` (pods labelled `version: v1`) and `v2` (pods labelled `version: v2`).
2.  The host-level `trafficPolicy.tls.mode` is **`ISTIO_MUTUAL`**. The `DestinationRule` has no `DISABLE` anywhere.
3.  Subset `v2` has its own `trafficPolicy` with **`loadBalancer.simple: RANDOM`**. Subset `v1` sets no load balancer.
4.  The `shuttle` pod's proxy holds a TLS transport socket for **both** subset clusters of `probe`, and the `lbPolicy` `RANDOM` for the `v2` cluster only (check with `istioctl proxy-config cluster`).
5.  Eight requests from the `shuttle` pod to `http://probe:8000/hostname` without extra headers return status `200` and are answered by `probe-v1` pods. Eight requests with the header `x-canary: true` return status `200` and are answered by the `probe-v2` pod.
6.  The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

The grader reads the `DestinationRule`, reads the `shuttle` pod's proxy configuration, and sends live requests, so the connections have to really work.

The lab ships three files in its `resources` folder. `astrona res` lists them. `count-pods.sh` counts which probe pod answers, `status-codes.sh` counts the status codes, and `drifter-call.sh` sends one request from the `drifter`.
