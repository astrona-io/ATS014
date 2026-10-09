---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, the spaceport arrival gate (the ingress gateway) is closed. Signals from outside the solar system for the bridge get no reply at all, even though a `Gateway` and a flight plan for the bridge both exist.

The planet `starfleet` holds the Starfleet:

* `bridge`: the flagship's page, a Service on port `9080`. It answers on `/productpage`.
* `cargo`, `navcom` and `scout` v1, v2 and v3: the rest of the fleet.
* `shuttle`: a client pod with `curl`.

Istio 1.30.5 is installed with Helm. The ingress gateway runs on the planet `istio-ingress`: its Deployment and its Service are both called `istio-ingress`, and the Service has type `ClusterIP`. Two Istio objects already exist in `starfleet`:

* A `Gateway` named `starfleet-gateway`, with one HTTP server on port `80` for the host `starfleet.example.com`. Something in it is wrong.
* A `VirtualService` named `bridge` (the flight plan) for the host `starfleet.example.com`, linked to `starfleet-gateway`, that sends `/productpage` and the bridge's other paths to `bridge` on port `9080`. **This flight plan is correct.**

`kind` has no load balancer, so reach the gate with a port forward, and send the `Host` header with every signal:

```bash
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
```

Fix the problem so that:

1.  The `Gateway` named `starfleet-gateway` in `starfleet` selects the ingress gateway pods in `istio-ingress`.
2.  It keeps **exactly one** server: port `80`, protocol `HTTP`, host `starfleet.example.com` only. Do **not** use `*`.
3.  The gateway's proxy has a listener on port `80`, and its route table holds the `bridge` routes for `starfleet.example.com`.
4.  All 10 out of 10 signals to `/productpage` with `Host: starfleet.example.com`, sent through the gateway Service, get `200`.
5.  A signal with `Host: other.example.com` does **not** get `200`.
6.  The `VirtualService` named `bridge` is **left unchanged**.
7.  Leave the gateway Deployment, its pod labels, the Starfleet Deployments and the Services unchanged.

The grader sends live signals from the `shuttle` pod to the gateway Service and reads the gateway's proxy, so the fix has to work, not merely exist.
