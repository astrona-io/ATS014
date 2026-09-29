# Question

Solve this question on: `terminal`

Namespace `edge` holds three identical backends, each on port 80:

* `native-app`
* `legacy-app`
* `modern-app`

Istio 1.30.5 is installed with the `demo` profile (so `istio-ingressgateway` is running in `istio-system`), and the **Gateway API CRDs are installed** with Istio's `istio` [`GatewayClass`](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) registered.

There is **no ingress configuration of any kind** — no [`Gateway`](https://istio.io/latest/docs/reference/config/networking/gateway/), no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/), no `Ingress`, no `IngressClass`, no [`HTTPRoute`](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/).

A self-signed certificate for `legacy.ica.local` is at **`/tmp/legacy.crt`** and **`/tmp/legacy.key`**.

Expose each application through a **different** one of the section's three APIs.

**A — `native-app`, via Istio's own objects**

1.  A `Gateway` named **`native-gw`** in `edge`, `apiVersion: networking.istio.io/v1`, selecting `istio: ingressgateway`, opening port **80**, protocol `HTTP`, for host **`native.ica.local`**.
2.  A `VirtualService` named **`native`** in `edge`, **bound to `native-gw`**, routing path prefix **`/api`** to `native-app` port 80.

**B — `legacy-app`, via the Kubernetes Ingress API**

3.  An `IngressClass` named **`istio`** with controller `istio.io/ingress-controller`.
4.  An `Ingress` named **`legacy`** in `edge` selecting that class, serving host **`legacy.ica.local`**, path **`/api`** with `pathType` **`Prefix`**, to `legacy-app` port 80.
5.  TLS for `legacy.ica.local` using a secret named **`legacy-credential`**, placed where the gateway can read it.

**C — `modern-app`, via the Kubernetes Gateway API**

6.  A `Gateway` named **`modern-gw`** in `edge`, `apiVersion: gateway.networking.k8s.io/v1`, `gatewayClassName` **`istio`**, one listener named `http` on port **80**, protocol `HTTP`, no hostname. Annotate it `networking.istio.io/service-type: ClusterIP` — this cluster is `kind`, which has no load balancer, and without that annotation the Service Istio creates for the Gateway never gets an address and the Gateway stays `Programmed=False`.
7.  An `HTTPRoute` named **`modern`** in `edge`, attached to `modern-gw`, for hostname **`modern.ica.local`**, path prefix **`/api`** to `modern-app` port 80.

**What the grader checks**

8.  Through **`istio-ingressgateway`**: `GET /api` with `Host: native.ica.local` returns **200** over HTTP, and `GET /api` with `Host: legacy.ica.local` returns **200** over **HTTPS**.
9.  Through the **`modern-gw-istio`** Service in `edge`: `GET /api` with `Host: modern.ica.local` returns **200**.
10. `modern-gw-istio` exists as a Deployment and Service **in `edge`** — the Gateway API object created its own proxy.
11. Both Gateway API objects report `Accepted=True` / `Programmed=True` and `Accepted=True` / `ResolvedRefs=True`.
12. `modern.ica.local` is **not** served by `istio-ingressgateway` — the two gateways are separate data planes.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [Gateway API](https://istio.io/latest/docs/reference/config/networking/gateway/) — `selector`, `servers`, `port`, `hosts` and the `tls` block
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [Istio Kubernetes Ingress task](https://istio.io/latest/docs/tasks/traffic-management/ingress/kubernetes-ingress/) — claiming an `Ingress` with `ingressClassName`, and the `pathType` rules
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
