# Question

Solve this question on: `terminal`

One `probe` pod in the `starfleet` namespace does all the work while the three other pods sit idle. Spread the requests over all four pods again.

The `starfleet` namespace runs:

* `probe-v1` (3 pods) and `probe-v2` (1 pod), all labelled `app: probe`, behind one Service `probe` on port `8000`. The path `/hostname` returns the name of the pod that served the request.
* `shuttle`, a client pod with `curl`.

Istio is installed, and every pod has its sidecar proxy (the Envoy proxy that Istio adds to each pod). A `DestinationRule` named `probe` already exists. Every request the `shuttle` pod sends to `probe` lands on the same pod.

Change the `probe` `DestinationRule` so that:

1.  The `DestinationRule` named `probe` in `starfleet` (host `probe`) uses **`simple: ROUND_ROBIN`** as its host-level `trafficPolicy.loadBalancer`.
2.  The `DestinationRule` contains **no `consistentHash`** anywhere.
3.  The `shuttle` pod's proxy holds a round robin cluster for `probe` (check it with `istioctl proxy-config cluster`).
4.  16 requests from the `shuttle` pod to `http://probe:8000/hostname` reach **all four** probe pods, and no pod answers more than 8 of them.
5.  The workloads stay as they are: `probe-v1` keeps 3 replicas, `probe-v2` keeps 1, no Deployment is added or removed, and the `probe` Service keeps selecting `app: probe`.

The grader reads the `DestinationRule`, reads the `shuttle` pod's proxy configuration, and sends live requests, so the spread has to really happen.
