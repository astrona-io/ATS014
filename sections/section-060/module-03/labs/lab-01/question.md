# Question

Solve this question on: `terminal`

Astronaut, your mission: build one shared arrival gate that crews on two different planets (namespaces) can both use.

Two namespaces, owned by two different teams:

* **`gwapi-demo`** — the platform team's namespace. Holds `booking-service` on port 80. The `Gateway` will live here.
* **`gwapi-team`** — an application team's namespace. Holds `catalog-service` on port 80.

Istio 1.30.5 is installed, the **Gateway API CRDs are installed**, and Istio has registered a `GatewayClass` named `istio`. There is **no `Gateway` and no `HTTPRoute`**, and therefore no gateway proxy anywhere.

Build a shared gateway that both teams can use.

**The Gateway (platform team)**

1.  Create a `Gateway` named **`shared-gateway`** in namespace **`gwapi-demo`**, with `gatewayClassName` **`istio`**. Annotate it `networking.istio.io/service-type: ClusterIP` — this cluster is `kind`, which has no load balancer, and without that annotation the Service Istio creates for the Gateway never gets an address and the Gateway stays `Programmed=False`.
2.  It must have **one** listener named **`http`**, on **port 80**, protocol **`HTTP`**, with **no `hostname`** so it accepts any host.
3.  Its `allowedRoutes` must permit routes from namespaces carrying the label **`gateway-access: "true"`** — use the **`Selector`** form. `All` is not acceptable; the point is a deliberate grant.
4.  Label **both** the **`gwapi-team`** namespace and the Gateway's own namespace **`gwapi-demo`** so they qualify. `Selector` grants nothing implicitly — a Gateway's own namespace is not exempt, and forgetting it leaves the route that lives beside the Gateway rejected while the cross-namespace one works.

**The routes**

5.  An `HTTPRoute` named **`booking`** in **`gwapi-demo`**, attached to `shared-gateway`, for hostname **`booking.ica.local`**, routing path prefix **`/book`** to `booking-service` port 80.
6.  An `HTTPRoute` named **`catalog`** in **`gwapi-team`**, attached to `shared-gateway` **in `gwapi-demo`** (a cross-namespace `parentRefs` needs a `namespace` field), for hostname **`catalog.ica.local`**, routing path prefix **`/items`** to `catalog-service` port 80.

**What the grader checks**

7.  A Deployment and Service named `shared-gateway-istio` exist **in `gwapi-demo`** — the `Gateway` created its own data plane. Nothing new appears in `istio-system`.
8.  The `Gateway` reports `Accepted=True` and `Programmed=True`.
9.  **Both** `HTTPRoute` objects report `Accepted=True` and `ResolvedRefs=True` on their parent. A cross-namespace route that the `Gateway` does not permit reports `Accepted=False` — that is the check this lab is built around.
10. `GET /book` with `Host: booking.ica.local` returns **200** through the new gateway.
11. `GET /items` with `Host: catalog.ica.local` returns **200** through the same gateway.
12. The `gwapi-team` namespace carries the `gateway-access=true` label.
