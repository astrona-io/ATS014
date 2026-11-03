# Question

Solve this question on: `terminal`

Requests from the `shuttle` pod to the `probe` fail, and the `probe` is meant to keep each `x-user` value on one pod. Fix the `probe` `DestinationRule` so that mesh clients work again and stickiness holds in both subsets.

The `starfleet` namespace runs:

* `probe-v1` (2 pods, label `version: v1`) and `probe-v2` (2 pods, label `version: v2`), all labelled `app: probe`, behind one Service `probe` on port `8000`. The path `/hostname` returns the name of the pod that served the request.
* `shuttle`, a client pod with `curl` and a sidecar proxy.
* A `PeerAuthentication` named `probe` with mode `STRICT` for the pods labelled `app: probe`.
* A `VirtualService` named `probe`: requests with the header `x-canary: true` go to subset `v2`, all other requests go to subset `v1`.
* A `DestinationRule` named `probe` that already exists and has the two mistakes.

The namespace `outpost` runs `drifter`, a client pod with no sidecar proxy.

Change the `probe` `DestinationRule` so that:

1.  It contains **no `tls.mode: DISABLE`** anywhere. The client TLS setting either is removed, or is **`ISTIO_MUTUAL`**.
2.  The host-level `loadBalancer.consistentHash` on the header `x-user` stays, and **no subset sets `loadBalancer.simple`**. Both subsets `v1` and `v2` stay defined.
3.  The `shuttle` pod's proxy holds a TLS transport socket and the `lbPolicy` `RING_HASH` for **both** subset clusters of `probe` (check with `istioctl proxy-config cluster`).
4.  Eight requests with the header `x-user: alice` return status `200` and are answered by **one** `probe-v1` pod. Eight requests with `x-user: alice` and `x-canary: true` return status `200` and are answered by **one** `probe-v2` pod.
5.  The `PeerAuthentication` stays `STRICT` and the workloads stay as they are. The `drifter` pod must still not get a `200` from the `probe`.

The grader reads the `DestinationRule`, reads the `shuttle` pod's proxy configuration, and sends live requests, so the fix has to really work.

The lab ships four files in its `resources` folder. `astrona res` lists them. `probe-destinationrule.yaml` is the starting `DestinationRule`, `count-pods.sh` counts which probe pod answers, `status-codes.sh` counts the status codes, and `drifter-call.sh` sends one request from the `drifter`.
