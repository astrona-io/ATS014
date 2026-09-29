# Question

Solve this question on: `terminal`

Namespace `ingress-demo` holds two applications that must be reachable from outside the cluster:

* `booking-service` — a Service on port 80
* `catalog-service` — a Service on port 80

Istio is installed with the `demo` profile, so `istio-ingressgateway` is running in `istio-system` — unconfigured, and currently answering 404 to everything. There is no [`Gateway`](https://istio.io/latest/docs/reference/config/networking/gateway/) and no [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/).

`kind` has no load balancer, so reach the gateway with a port-forward:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

Expose both applications through the **one shared gateway**, separated by hostname.

1.  Create a `Gateway` named **`public-gateway`** in namespace **`ingress-demo`**, selecting the standard ingress gateway pods (`istio: ingressgateway`).
2.  It must open **one** server on **port 80**, protocol **`HTTP`**, accepting exactly these two hosts:
    *   `booking.ica.local`
    *   `catalog.ica.local`
    Do **not** use `*`. The listener must reject any other host.
3.  Create a `VirtualService` named **`booking`** for host `booking.ica.local`, **bound to `public-gateway`**, routing URI prefix **`/book`** to `booking-service` on port 80.
4.  Create a `VirtualService` named **`catalog`** for host `catalog.ica.local`, **bound to `public-gateway`**, routing URI prefix **`/items`** to `catalog-service` on port 80.

**What the grader checks**

5.  `GET /book` with `Host: booking.ica.local` returns **200**.
6.  `GET /items` with `Host: catalog.ica.local` returns **200**.
7.  `GET /book` with `Host: unknown.ica.local` does **not** return 200 — the listener only accepts the two named hosts.
8.  `GET /book` with `Host: catalog.ica.local` does **not** return 200 — each host only carries its own routes.
9.  Both hosts appear in the gateway proxy's route table. A `VirtualService` that exists but is not bound to the gateway fails this check even though the objects look correct.
10. Both `VirtualService` objects name the gateway in their `gateways` field.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [Gateway API](https://istio.io/latest/docs/reference/config/networking/gateway/) — `selector`, `servers`, `port`, `hosts` and the `tls` block
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
