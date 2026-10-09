# Question

Solve this question on: `terminal`

Three teams want their applications reachable from outside the cluster, and each team uses a different ingress API. Expose all three on the same cluster at the same time, and prove which gateway proxy answers which request.

Namespace `edge` holds three identical backends, each on port 80:

* `native-app`
* `legacy-app`
* `modern-app`

Istio 1.30.5 is installed with the `demo` profile, so the ingress gateway proxy `istio-ingressgateway` runs in `istio-system`. The **Gateway API custom resource definitions (CRDs) are installed**, and Istio has registered its `GatewayClass` named `istio`.

There is **no ingress configuration of any kind**: no `Gateway`, no `VirtualService`, no `Ingress`, no `IngressClass` and no `HTTPRoute`.

A self-signed certificate for `legacy.ica.local` is at **`/tmp/legacy.crt`**, with its private key at **`/tmp/legacy.key`**.

Expose each application through a **different** ingress API.

**A: `native-app`, through Istio's own objects**

1.  A `Gateway` named **`native-gw`** in `edge`, with `apiVersion: networking.istio.io/v1`, that selects `istio: ingressgateway` and opens port **80**, protocol `HTTP`, for the host **`native.ica.local`**.
2.  A `VirtualService` named **`native`** in `edge`, **bound to `native-gw`** in its `gateways` field, that sends the path prefix **`/api`** to `native-app` port 80.

**B: `legacy-app`, through the Kubernetes Ingress API**

3.  An `IngressClass` named **`istio`** with the controller `istio.io/ingress-controller`.
4.  An `Ingress` named **`legacy`** in `edge` that uses that class and serves the host **`legacy.ica.local`**, path **`/api`** with `pathType` **`Prefix`**, to `legacy-app` port 80.
5.  TLS for `legacy.ica.local`, with the certificate in a secret named **`legacy-credential`**. Put the secret in the namespace where the gateway proxy can read it.

**C: `modern-app`, through the Kubernetes Gateway API**

6.  A `Gateway` named **`modern-gw`** in `edge`, with `apiVersion: gateway.networking.k8s.io/v1` and `gatewayClassName` **`istio`**, with one listener named `http` on port **80**, protocol `HTTP`, and no hostname. Give it the annotation `networking.istio.io/service-type: ClusterIP`. This cluster is `kind`, which has no load balancer. Without the annotation, the Service that Istio creates for the `Gateway` never gets an address, and the `Gateway` stays `Programmed=False`.
7.  An `HTTPRoute` named **`modern`** in `edge`, attached to `modern-gw`, for the host name **`modern.ica.local`**, that sends the path prefix **`/api`** to `modern-app` port 80.

**What the grader checks**

8.  The objects above exist with the names, selector, hosts, class, controller and `pathType` given.
9.  The secret `legacy-credential` is in the namespace of the gateway proxy that serves the `Ingress`.
10. A Deployment and a Service named `modern-gw-istio` exist **in `edge`**, with a ready pod: the Gateway API `Gateway` created its own proxy.
11. The Gateway API `Gateway` `modern-gw` reports `Accepted=True` and `Programmed=True`, and the `HTTPRoute` `modern` reports `Accepted=True` and `ResolvedRefs=True`.
12. Through **`istio-ingressgateway`**: `GET /api` with `Host: native.ica.local` returns **200** over HTTP, and `GET /api` for `legacy.ica.local` returns **200** over **HTTPS**.
13. Through the **`modern-gw-istio`** Service in `edge`: `GET /api` with `Host: modern.ica.local` returns **200**.
14. `istio-ingressgateway` does **not** return `200` for `modern.ica.local`: the two gateways are separate proxies.
