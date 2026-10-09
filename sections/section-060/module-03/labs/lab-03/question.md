# Question

Solve this question on: `terminal`

The gateway in the `starfleet` namespace is up, but the two `HTTPRoute` objects behind it are broken. Requests for the `bridge` page fail, and requests for `scout` never find a route. Find out why, and fix both.

The `starfleet` namespace holds the sample app:

* `bridge`: the web frontend, behind the `bridge` Service on port `9080`. Its page is at `/productpage`.
* `scout` v1, v2 and v3: behind one `scout` Service on port `9080`. It answers at `/reviews/0`.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `cargo` and `navcom`: the other backends of the app.

Istio 1.30.5 and the Gateway API custom resource definitions (CRDs) are installed. Three objects exist:

* A Gateway API `Gateway` named `starfleet-gateway`, with one HTTP listener named `http` on port 80 for the host name `starfleet.example.com`. Istio deployed its proxy and the Service `starfleet-gateway-istio`. **This `Gateway` is correct.**
* An `HTTPRoute` named `bridge`, meant to send the path prefix `/productpage` to the `bridge` Service.
* An `HTTPRoute` named `scout`, meant to send the path prefix `/reviews` to the `scout` Service.

Each `HTTPRoute` has one fault. Fix them so that:

1.  Both `HTTPRoute` objects, `bridge` and `scout` in `starfleet`, attach to the `Gateway` **`starfleet-gateway`** and report **`Accepted=True`** and **`ResolvedRefs=True`** for it.
2.  The `Gateway`'s listener reports **2** attached routes.
3.  Both routes keep their host name **`starfleet.example.com`**, their `PathPrefix` paths (`/productpage` and `/reviews`) and their backend port **`9080`**. `bridge` sends to the **`bridge`** Service, and `scout` to the **`scout`** Service.
4.  10 out of 10 requests sent from the `shuttle` pod to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.
5.  10 out of 10 requests sent the same way to `/reviews/0` return **`200`**.
6.  The `Gateway` is **left unchanged**, and it stays the only `Gateway` in `starfleet`. Do not add, rename or remove Services or Deployments: fix the routes, not the app.

The grader reads the status of both routes and sends real requests through the gateway from the `shuttle` pod, so the fix has to work, not only exist.
