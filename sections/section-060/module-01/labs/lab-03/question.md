---
estimated_duration: 25m
---

# Question

Solve this question on: `terminal`

The Starfleet's front door is broken. Requests from outside the cluster for `bridge` do not get through. The last team on duty wrote a `Gateway` and a `VirtualService`, and made more than one mistake. Find every fault and make `bridge` reachable again.

The `starfleet` namespace runs these workloads:

* `bridge`: the web frontend, behind a Service on port `9080`. It answers on `/productpage` and `/api/v1/products`.
* `cargo`, `navcom` and `scout` v1, v2 and v3: other backends of the application.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed with Helm. The ingress gateway (the Envoy proxy that accepts traffic from outside the cluster) runs in the `istio-ingress` namespace. Its Deployment and its Service are both called `istio-ingress`, its pods carry the label `istio: ingress`, and the Service has type `ClusterIP`. Two Istio objects already exist in `starfleet`:

* A `Gateway` named `starfleet-gateway`.
* A `VirtualService` named `bridge` for the `bridge` paths.

`kind` has no load balancer, so reach the gateway with a port forward, and send the `Host` header with every request:

```bash
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
```

Fix the problem so that:

1.  The `Gateway` named `starfleet-gateway` in `starfleet` selects the gateway pods (`istio: ingress`) and has **exactly one** server: port `80`, protocol `HTTP`, host `starfleet.example.com` only. Do **not** use `*`.
2.  The `VirtualService` named `bridge` in `starfleet` serves the host `starfleet.example.com` and is **bound to `starfleet-gateway`** with its `gateways` field.
3.  Every route in it goes to the `bridge` Service on port `9080`. Do not create a new Service to match a wrong name.
4.  The gateway's proxy holds a `/productpage` route for `starfleet.example.com` from the `bridge` `VirtualService`, and a healthy endpoint for `bridge`.
5.  All 10 out of 10 requests to `/productpage` with `Host: starfleet.example.com`, sent through the gateway Service, get `200`. `/api/v1/products` gets `200` too.
6.  A request with `Host: other.example.com` does **not** get `200`, and `/admin` with `Host: starfleet.example.com` gets `404` (no catch-all route).
7.  Leave the gateway Deployment, its pod labels, the `starfleet` Deployments and the Services unchanged. Do not add or remove workloads.

The grader sends live requests from the `shuttle` pod to the gateway Service and reads the gateway's proxy configuration, so the fix has to work, not only exist.
