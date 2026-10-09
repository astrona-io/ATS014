---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, the bridge crew has written a flight plan for signals from outside the solar system, but the gate it names was never built. Build it.

The planet `starfleet` holds the Starfleet:

* `bridge`: the flagship page, behind the `bridge` Service on port `9080`. Its page lives at `/productpage`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `cargo`, `navcom` and `scout` v1, v2 and v3: the rest of the fleet.

Istio 1.30.5 is installed, the **Gateway API objects are installed**, and Istio has registered the `GatewayClass` named `istio`. There is no ingress gateway anywhere.

One object already exists: an `HTTPRoute` named `bridge` in `starfleet`. It docks at a `Gateway` named `starfleet-gateway`, for the host name `starfleet.example.com`, and sends the path prefix `/productpage` to the `bridge` Service on port `9080`. **This route is correct.** Right now it has no status, because the gate it names does not exist.

Build the gate so that:

1.  A Gateway API `Gateway` named **`starfleet-gateway`** exists in namespace **`starfleet`**, with `gatewayClassName` **`istio`**.
2.  It carries the annotation **`networking.istio.io/service-type: ClusterIP`**. This cluster is `kind`, which has no load balancer, so without it the gate never gets an address.
3.  It has exactly **one** listener, named **`http`**, on **port 80**, protocol **`HTTP`**, for the host name **`starfleet.example.com`**.
4.  Only routes from the gate's own namespace may dock. Keep `allowedRoutes` at **`from: Same`** (or leave it out, which means the same).
5.  Istio built the gate's proxy: a Deployment and a Service named **`starfleet-gateway-istio`** in **`starfleet`**, with a ready pod. Nothing new appears in `istio-system`.
6.  The `Gateway` reports **`Accepted=True`** and **`Programmed=True`**.
7.  The `HTTPRoute` `bridge` reports **`Accepted=True`** and **`ResolvedRefs=True`** on its gate.
8.  10 out of 10 signals sent from the `shuttle` to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.
9.  A signal to the same address with **`Host: other.example.com`** returns **`404`**.
10. The `HTTPRoute` `bridge` is **left unchanged**. Leave the Deployments and Services of the fleet unchanged too.

The grader reads the status of both objects and sends live signals through the gate from the `shuttle` pod, so the gate has to work, not merely exist.
