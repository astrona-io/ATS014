---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The Starfleet's front door is closed. Requests from outside the cluster for `bridge` get no response at all, even though a `Gateway` and a `VirtualService` for `bridge` both exist.

The `starfleet` namespace runs these workloads:

* `bridge`: the web frontend, behind a Service on port `9080`. It answers on `/productpage`.
* `cargo`, `navcom` and `scout` v1, v2 and v3: other backends of the application.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed with Helm. The ingress gateway (the Envoy proxy that accepts traffic from outside the cluster) runs in the `istio-ingress` namespace. Its Deployment and its Service are both called `istio-ingress`, and the Service has type `ClusterIP`. Two Istio objects already exist in `starfleet`:

* A `Gateway` named `starfleet-gateway`, with one HTTP server on port `80` for the host `starfleet.example.com`. Something in it is wrong.
* A `VirtualService` named `bridge` for the host `starfleet.example.com`, bound to `starfleet-gateway`, that sends `/productpage` and the other `bridge` paths to `bridge` on port `9080`. **This `VirtualService` is correct.**

`kind` has no load balancer, so reach the gateway with a port forward, and send the `Host` header with every request:

```bash
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
```

Fix the problem so that:

1.  The `Gateway` named `starfleet-gateway` in `starfleet` selects the ingress gateway pods in `istio-ingress`.
2.  It keeps **exactly one** server: port `80`, protocol `HTTP`, host `starfleet.example.com` only. Do **not** use `*`.
3.  The gateway's proxy has a listener on port `80`, and its route table holds the `bridge` routes for `starfleet.example.com`.
4.  All 10 out of 10 requests to `/productpage` with `Host: starfleet.example.com`, sent through the gateway Service, get `200`.
5.  A request with `Host: other.example.com` does **not** get `200`.
6.  The `VirtualService` named `bridge` is **left unchanged**.
7.  Leave the gateway Deployment, its pod labels, the `starfleet` Deployments and the Services unchanged.

The grader sends live requests from the `shuttle` pod to the gateway Service and reads the gateway's proxy configuration, so the fix has to work, not only exist.
