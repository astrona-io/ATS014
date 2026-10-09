# Question

Solve this question on: `terminal`

Two teams in two namespaces both need requests from outside the cluster. Build one shared Gateway API `Gateway` that both teams can use.

The two namespaces belong to two different teams:

* **`gwapi-demo`**: the platform team's namespace. It holds `booking-service` on port 80. The `Gateway` goes here.
* **`gwapi-team`**: an application team's namespace. It holds `catalog-service` on port 80.

Istio 1.30.5 is installed, the **Gateway API custom resource definitions (CRDs) are installed**, and Istio has registered a `GatewayClass` named `istio`. There is **no Gateway API `Gateway` and no `HTTPRoute`**, so no gateway proxy for the Gateway API runs yet. (Istio's own `istio-ingressgateway` runs in `istio-system`, but it plays no part in this task.)

**The Gateway (platform team)**

1.  Create a `Gateway` named **`shared-gateway`** in namespace **`gwapi-demo`**, with `gatewayClassName` **`istio`**. Give it the annotation `networking.istio.io/service-type: ClusterIP`. This cluster is `kind`, which has no load balancer. Without the annotation, the Service that Istio creates for the `Gateway` never gets an address, and the `Gateway` stays `Programmed=False`.
2.  It must have **one** listener named **`http`**, on **port 80**, protocol **`HTTP`**, with **no `hostname`**, so that it accepts any host.
3.  Its `allowedRoutes` must allow routes from namespaces that carry the label **`gateway-access: "true"`**. Use the **`Selector`** form. `All` is not accepted: the task asks for a deliberate grant.
4.  Label **both** the **`gwapi-team`** namespace and the `Gateway`'s own namespace **`gwapi-demo`** so that they match. A `Selector` does not include the `Gateway`'s own namespace for free. If you forget it, the route next to the `Gateway` is refused while the route from the other namespace works.

**The routes**

5.  An `HTTPRoute` named **`booking`** in **`gwapi-demo`**, attached to `shared-gateway`, for the host name **`booking.ica.local`**, that sends the path prefix **`/book`** to `booking-service` port 80.
6.  An `HTTPRoute` named **`catalog`** in **`gwapi-team`**, attached to `shared-gateway` **in `gwapi-demo`**, for the host name **`catalog.ica.local`**, that sends the path prefix **`/items`** to `catalog-service` port 80. A `parentRefs` entry that points at another namespace needs a `namespace` field.

**What the grader checks**

7.  The `Gateway` has the class, listener and `allowedRoutes` selector described above.
8.  A Deployment and a Service named `shared-gateway-istio` exist **in `gwapi-demo`**, and the Deployment has a ready pod: the `Gateway` created its own proxy.
9.  The `Gateway` reports `Accepted=True` and `Programmed=True`.
10. **Both** `HTTPRoute` objects report `Accepted=True` and `ResolvedRefs=True` for their parent `Gateway`. A route from a namespace that the `Gateway` does not allow reports `Accepted=False`; that is the check this lab is built around.
11. The `catalog` route's `parentRefs` names the namespace `gwapi-demo`.
12. The `gwapi-team` namespace carries the label `gateway-access=true`.
13. `GET /book` with `Host: booking.ica.local` returns **200** through the new gateway.
14. `GET /items` with `Host: catalog.ica.local` returns **200** through the same gateway.
