---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The `starfleet` namespace was opened to outside traffic with a Kubernetes `Ingress` and an ingress class for Istio. Kubernetes accepted every object and `kubectl` reports no error, yet no request for `starfleet.example.com` gets through the ingress gateway.

The `starfleet` namespace holds:

* `probe-v1` and `probe-v2`: an HTTP echo server behind one `probe` Service on port `8000`. It answers any path under `/anything`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.

Istio 1.30.5 is installed in `istio-system`, with its ingress gateway: the Deployment and Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`. Inside the cluster, you reach the gateway at `http://istio-ingressgateway.istio-system`.

Two objects already exist:

* An `Ingress` named `starfleet` in `starfleet`. It names the ingress class `istio` and sends host `starfleet.example.com`, path `/anything` (`pathType: Prefix`) to `probe` on port `8000`. **This Ingress is correct.**
* An `IngressClass` named `istio`. Something in it is wrong.

Fix the problem so that:

1.  The `IngressClass` named `istio` exists and names Istio's ingress controller, `istio.io/ingress-controller`.
2.  The `Ingress` named `starfleet` is **left unchanged**: it still names the class `istio` and has its one rule.
3.  5 out of 5 requests sent from the `shuttle` pod to `http://istio-ingressgateway.istio-system/anything/dock/<n>` with the header `Host: starfleet.example.com` get `200`.
4.  A request to `/status/200` on the same host still gets `404` from the gateway: only `/anything` is routed.
5.  No `Gateway` and no `VirtualService` exist anywhere in the cluster. The gateway must serve the `Ingress` itself.
6.  The Deployments, the Services and the ingress gateway stay unchanged.

The grader sends live requests from the `shuttle` pod through the gateway, so the fix has to work, not only exist.
