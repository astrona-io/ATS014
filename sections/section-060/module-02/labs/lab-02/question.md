---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, the arrival gate has gone quiet. A teammate opened the planet `starfleet` to outside signals with a Kubernetes `Ingress` and an ingress class for Istio. Every object was accepted, `kubectl` reports no error, and yet no signal for `starfleet.example.com` gets through the gate.

The planet `starfleet` holds:

* `probe-v1` and `probe-v2`: the echo probe behind one `probe` Service on port `8000`. It answers any path under `/anything`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.

Istio 1.30.5 is installed in `istio-system`, with its ingress gateway: the Deployment and Service `istio-ingressgateway`, pods labelled `istio: ingressgateway`. Inside the cluster you reach the gate at `http://istio-ingressgateway.istio-system`.

Two objects already exist:

* An `Ingress` named `starfleet` in `starfleet`. It claims the ingress class `istio` and sends host `starfleet.example.com`, path `/anything` (`pathType: Prefix`) to `probe` on port `8000`. **This Ingress is correct.**
* An `IngressClass` named `istio`. Something in it is wrong.

Fix the problem so that:

1.  The `IngressClass` named `istio` exists and names Istio's ingress controller, `istio.io/ingress-controller`.
2.  The `Ingress` named `starfleet` is **left unchanged**: still claiming the class `istio`, with its one rule.
3.  5 out of 5 signals sent from the `shuttle` to `http://istio-ingressgateway.istio-system/anything/dock/<n>` with the header `Host: starfleet.example.com` get `200`.
4.  A signal to `/status/200` on the same host still gets `404` from the gate: only `/anything` is routed.
5.  No `Gateway` and no `VirtualService` exist anywhere in the cluster. The gate must serve the `Ingress` itself.
6.  Leave the Deployments, the Services and the ingress gateway unchanged.

The grader sends live signals from the `shuttle` pod through the gate, so the fix has to work, not merely exist.
