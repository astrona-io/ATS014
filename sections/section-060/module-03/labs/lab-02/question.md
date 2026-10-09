# Question

Solve this question on: `terminal`

The `bridge` team in the `starfleet` namespace has written an `HTTPRoute` for requests from outside the cluster, but the `Gateway` it names was never created. Create it.

The `starfleet` namespace holds the sample app:

* `bridge`: the web frontend, behind the `bridge` Service on port `9080`. Its page is at `/productpage`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `cargo`, `navcom` and `scout` v1, v2 and v3: the other backends of the app.

Istio 1.30.5 is installed, the **Gateway API custom resource definitions (CRDs) are installed**, and Istio has registered the `GatewayClass` named `istio`. No ingress gateway runs anywhere, and `istio-system` holds only `istiod`.

One object already exists: an `HTTPRoute` named `bridge` in `starfleet`. Its `parentRefs` names a `Gateway` called `starfleet-gateway`. It serves the host name `starfleet.example.com` and sends the path prefix `/productpage` to the `bridge` Service on port `9080`. **This route is correct.** Right now it has no status, because the `Gateway` it names does not exist.

Create the `Gateway` so that:

1.  A Gateway API `Gateway` named **`starfleet-gateway`** exists in namespace **`starfleet`**, with `gatewayClassName` **`istio`**.
2.  It carries the annotation **`networking.istio.io/service-type: ClusterIP`**. This cluster is `kind`, which has no load balancer, so without the annotation the gateway's Service never gets an address.
3.  It has exactly **one** listener, named **`http`**, on **port 80**, protocol **`HTTP`**, for the host name **`starfleet.example.com`**.
4.  Only routes from the `Gateway`'s own namespace may attach. Keep `allowedRoutes` at **`from: Same`** (or leave it out, which means the same).
5.  Istio deployed the gateway's proxy: a Deployment and a Service named **`starfleet-gateway-istio`** in **`starfleet`**, with a ready pod. `istio-system` still holds only `istiod`.
6.  The `Gateway` reports **`Accepted=True`** and **`Programmed=True`**.
7.  The `HTTPRoute` `bridge` reports **`Accepted=True`** and **`ResolvedRefs=True`** for this `Gateway`.
8.  10 out of 10 requests sent from the `shuttle` pod to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.
9.  A request to the same address with **`Host: other.example.com`** returns **`404`**.
10. The `HTTPRoute` `bridge` is **left unchanged**. Leave the Deployments and Services of the app unchanged too.

The grader reads the status of both objects and sends real requests through the gateway from the `shuttle` pod, so the gateway has to work, not only exist.
