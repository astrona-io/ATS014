# Solution Walkthrough

The solution is three objects and two namespace labels. The labels let the route from the other namespace attach to the `Gateway`. If you forget one, the Gateway API reports the failure clearly in the status of the route. The Gateway API is the Kubernetes API for gateways and routes: a `Gateway` opens listeners, and an `HTTPRoute` holds the routing rules. The walkthrough does items 1 to 3 (the `Gateway`) and items 5 and 6 (the routes) first, so that you see the routes refused. Then item 4 (the labels) fixes it. Items 7 to 14 prove the result.

---

## Start: Confirm The Prerequisites

The task says that the Gateway API CRDs (custom resource definitions) are installed, that Istio registered a `GatewayClass` named `istio`, and that no `Gateway` and no `HTTPRoute` exist. Check this. Also check that neither namespace has the label `gateway-access` yet. Save the identity of the workloads for item 12:

```sh
kubectl get crd | grep gateway.networking.k8s.io | awk '{print $1}'
kubectl get gatewayclass
kubectl get ns gwapi-demo gwapi-team --show-labels
kubectl -n gwapi-demo get gateway,httproute
kubectl -n gwapi-team get httproute
for ns in gwapi-demo gwapi-team; do
  kubectl -n $ns get deploy,svc -o custom-columns=NS:.metadata.namespace,KIND:.kind,NAME:.metadata.name,UID:.metadata.uid | grep -v NS
done
```

```text
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
NAME           CONTROLLER                    ACCEPTED   AGE
istio          istio.io/gateway-controller   True       12s
istio-remote   istio.io/unmanaged-gateway    True       12s
NAME         STATUS   AGE   LABELS
gwapi-demo   Active   8s    istio-injection=enabled,kubernetes.io/metadata.name=gwapi-demo
gwapi-team   Active   8s    istio-injection=enabled,kubernetes.io/metadata.name=gwapi-team
No resources found in gwapi-demo namespace.
No resources found in gwapi-team namespace.
gwapi-demo   Deployment   booking-service-v1   52283dce-7cc7-4509-a1aa-34baedb87c84
gwapi-demo   Service      booking-service      55e4353a-807c-4fe3-b779-e7fd19791762
gwapi-team   Deployment   catalog-service-v1   6daf7ea6-e0df-4c94-b4c7-6ccafc6a034f
gwapi-team   Service      catalog-service      36d9a18f-eee4-41e4-8fbc-797ec895a517
```

The CRDs are present. The `istio` `GatewayClass` is accepted. Istio also creates `istio-remote`, which this task does not use. The controller name of the class is `istio.io/gateway-controller`. That is a different name from `istio.io/ingress-controller`, the controller for the older Kubernetes `Ingress` object: the two APIs have separate controllers. Neither namespace has the label `gateway-access`.

---

## Items 1 To 3: The `Gateway`

> **Task item 1:** Create a `Gateway` named **`shared-gateway`** in namespace **`gwapi-demo`**, with `gatewayClassName` **`istio`**. Give it the annotation `networking.istio.io/service-type: ClusterIP`. This cluster is `kind`, which has no load balancer. Without the annotation, the Service that Istio creates for the `Gateway` never gets an address, and the `Gateway` stays `Programmed=False`.
>
> **Task item 2:** It must have **one** listener named **`http`**, on **port 80**, protocol **`HTTP`**, with **no `hostname`**, so that it accepts any host.
>
> **Task item 3:** Its `allowedRoutes` must allow routes from namespaces that carry the label **`gateway-access: "true"`**. Use the **`Selector`** form. `All` is not accepted: the task asks for a deliberate grant.

The three items describe one object. A few details matter:

- There is no `selector` field. The Gateway API uses `gatewayClassName` instead, and Istio creates the proxy for the `Gateway` rather than finding one.
- The listener has no `hostname`, so it accepts any host, and the routes decide by their `hostnames`.
- `from: Selector` with the label is a deliberate grant that you can take back. `from: All` would let the traffic through, but the task does not accept it.

Save this as `gateway-shared-gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gwapi-demo
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: "true"
```

Apply it:

```sh
kubectl apply -f gateway-shared-gateway.yaml
```

```text
gateway.gateway.networking.k8s.io/shared-gateway created
```

Check items 1 to 3. Wait for the proxy that Istio creates, and list what Istio created. Confirm that nothing for this `Gateway` appeared in `istio-system`. Then print the annotations and the spec:

```sh
kubectl -n gwapi-demo rollout status deployment shared-gateway-istio --timeout=120s
kubectl -n gwapi-demo get deploy,svc -l gateway.networking.k8s.io/gateway-name=shared-gateway
kubectl -n istio-system get deploy | grep shared || echo "(nothing in istio-system)"
kubectl -n gwapi-demo get gateway shared-gateway -o jsonpath='{.metadata.annotations.networking\.istio\.io/service-type}{"\n"}{.spec}{"\n"}'
```

```text
Waiting for deployment "shared-gateway-istio" rollout to finish: 0 of 1 updated replicas are available...
deployment "shared-gateway-istio" successfully rolled out
NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/shared-gateway-istio   1/1     1            1           2s

NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)            AGE
service/shared-gateway-istio   ClusterIP   10.96.147.165   <none>        15021/TCP,80/TCP   2s
(nothing in istio-system)
ClusterIP
{"gatewayClassName":"istio","listeners":[{"allowedRoutes":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"gateway-access":"true"}}}},"name":"http","port":80,"protocol":"HTTP"}]}
```

You created one object, and Istio created a Deployment and a Service named `shared-gateway-istio` in `gwapi-demo`. The Service has the type `ClusterIP` because of the annotation. Without it, Istio creates a `LoadBalancer` Service that stays at `<pending>` on `kind`. The spec has the class `istio`, one listener named `http` on port 80 with the protocol `HTTP` and no `hostname`, and the `Selector` form of `allowedRoutes`.

---

## Item 5: The Route Next To The `Gateway`

> **Task item 5:** An `HTTPRoute` named **`booking`** in **`gwapi-demo`**, attached to `shared-gateway`, for the host name **`booking.ica.local`**, that sends the path prefix **`/book`** to `booking-service` port 80.

This route lives in the same namespace as the `Gateway`, so `parentRefs` needs no `namespace`. Save this as `httproute-booking.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: booking
  namespace: gwapi-demo
spec:
  parentRefs:
    - name: shared-gateway
  hostnames:
    - booking.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /book
      backendRefs:
        - name: booking-service
          port: 80
```

Apply it:

```sh
kubectl apply -f httproute-booking.yaml
```

```text
httproute.gateway.networking.k8s.io/booking created
```

---

## Item 6: The Route In The Other Namespace

> **Task item 6:** An `HTTPRoute` named **`catalog`** in **`gwapi-team`**, attached to `shared-gateway` **in `gwapi-demo`**, for the host name **`catalog.ica.local`**, that sends the path prefix **`/items`** to `catalog-service` port 80. A `parentRefs` entry that points at another namespace needs a `namespace` field.

The `namespace: gwapi-demo` in `parentRefs` is required here. Without it, the route looks for a `Gateway` named `shared-gateway` in its own namespace, `gwapi-team`, where none exists. The `backendRefs` entry has no namespace, because the backend is in the namespace of the route, which is the normal case. A route that sends to a Service in another namespace needs a `ReferenceGrant` in that namespace. That is a Gateway API object that allows references from another namespace. Save this as `httproute-catalog.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: catalog
  namespace: gwapi-team
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gwapi-demo
  hostnames:
    - catalog.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /items
      backendRefs:
        - name: catalog-service
          port: 80
```

Apply it:

```sh
kubectl apply -f httproute-catalog.yaml
```

```text
httproute.gateway.networking.k8s.io/catalog created
```

The Gateway API reports what is wrong in the status of each object. Read the conditions of both routes. This is a big practical advantage over the Kubernetes `Ingress` API:

```sh
kubectl -n gwapi-demo get httproute booking \
  -o jsonpath='booking: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
kubectl -n gwapi-team get httproute catalog \
  -o jsonpath='catalog: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
```

```text
booking: Accepted=False(NotAllowedByListeners) ResolvedRefs=True(ResolvedRefs) 
catalog: Accepted=False(NotAllowedByListeners) ResolvedRefs=True(ResolvedRefs) 
```

Both routes are refused: `Accepted=False` with the reason `NotAllowedByListeners`. The `Selector` of the `Gateway` matches no namespace yet, because no namespace has the label. `ResolvedRefs=True` shows that the backend Services are fine. Only the attachment to the `Gateway` failed.

---

## Item 4: Label Both Namespaces

> **Task item 4:** Label **both** the **`gwapi-team`** namespace and the `Gateway`'s own namespace **`gwapi-demo`** so that they match. A `Selector` does not include the `Gateway`'s own namespace for free. If you forget it, the route next to the `Gateway` is refused while the route from the other namespace works.

The labels are the grant. First label only the team namespace, which is the obvious step, and read the conditions again:

```sh
kubectl label namespace gwapi-team gateway-access=true
sleep 5
kubectl -n gwapi-demo get httproute booking \
  -o jsonpath='booking: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
kubectl -n gwapi-team get httproute catalog \
  -o jsonpath='catalog: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
```

```text
namespace/gwapi-team labeled
booking: Accepted=False(NotAllowedByListeners) ResolvedRefs=True(ResolvedRefs) 
catalog: Accepted=True(Accepted) ResolvedRefs=True(ResolvedRefs) 
```

The route from `gwapi-team` attaches, and the route next to the `Gateway` is still refused. A `Selector` allows only the namespaces whose labels match, and the own namespace of the `Gateway` is not an exception. Label `gwapi-demo` as well:

```sh
kubectl label namespace gwapi-demo gateway-access=true
sleep 5
kubectl -n gwapi-demo get httproute booking \
  -o jsonpath='booking: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
kubectl -n gwapi-team get httproute catalog \
  -o jsonpath='catalog: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
kubectl get ns gwapi-demo gwapi-team --show-labels
```

```text
namespace/gwapi-demo labeled
booking: Accepted=True(Accepted) ResolvedRefs=True(ResolvedRefs) 
catalog: Accepted=True(Accepted) ResolvedRefs=True(ResolvedRefs) 
NAME         STATUS   AGE   LABELS
gwapi-demo   Active   27s   gateway-access=true,istio-injection=enabled,kubernetes.io/metadata.name=gwapi-demo
gwapi-team   Active   27s   gateway-access=true,istio-injection=enabled,kubernetes.io/metadata.name=gwapi-team
```

Both routes are accepted, and both namespaces carry the label `gateway-access=true`. This also answers item 12.

---

## Items 7 And 9: The `Gateway` Is Accepted And Programmed

> **Task item 7:** The `Gateway` has the class, listener and `allowedRoutes` selector described above.
>
> **Task item 9:** The `Gateway` reports `Accepted=True` and `Programmed=True`.

The spec from items 1 to 3 shows the class, the listener and the selector. Read the conditions of the `Gateway`:

```sh
kubectl -n gwapi-demo get gateway shared-gateway -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
```

```text
Accepted=True Programmed=True 
```

The `Gateway` is accepted, and its proxy is programmed. Without the annotation `networking.istio.io/service-type: ClusterIP`, `Programmed` would stay `False` on `kind`.

---

## Item 8: The `Gateway` Created Its Own Proxy

> **Task item 8:** A Deployment and a Service named `shared-gateway-istio` exist **in `gwapi-demo`**, and the Deployment has a ready pod: the `Gateway` created its own proxy.

The output of items 1 to 3 shows it: the Deployment `shared-gateway-istio` shows `1/1` ready, and the Service `shared-gateway-istio` exists in `gwapi-demo`. Nothing for this `Gateway` is in `istio-system`.

---

## Items 10 And 11: Both Routes Are Accepted, And The Parent Names A Namespace

> **Task item 10:** **Both** `HTTPRoute` objects report `Accepted=True` and `ResolvedRefs=True` for their parent `Gateway`. A route from a namespace that the `Gateway` does not allow reports `Accepted=False`; that is the check this lab is built around.
>
> **Task item 11:** The `catalog` route's `parentRefs` names the namespace `gwapi-demo`.

The output of item 4 shows the four `True` values for the two routes. A route from a namespace that the `Gateway` does not allow reports `Accepted=False`. Remove the label from `gwapi-demo` once, to see it, and then put it back. Print the `parentRefs` of the `catalog` route first:

```sh
kubectl -n gwapi-team get httproute catalog -o jsonpath='{.spec.parentRefs}{"\n"}'
kubectl label namespace gwapi-demo gateway-access-
sleep 4
kubectl -n gwapi-demo get httproute booking \
  -o jsonpath='booking: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
kubectl label namespace gwapi-demo gateway-access=true
sleep 4
kubectl -n gwapi-demo get httproute booking \
  -o jsonpath='booking: {range .status.parents[0].conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}'
```

```text
[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"shared-gateway","namespace":"gwapi-demo"}]
namespace/gwapi-demo unlabeled
booking: Accepted=False(NotAllowedByListeners) ResolvedRefs=True(ResolvedRefs) 
namespace/gwapi-demo labeled
booking: Accepted=True(Accepted) ResolvedRefs=True(ResolvedRefs) 
```

The `parentRefs` of `catalog` names the namespace `gwapi-demo`. Without the label, the route refuses with the reason `NotAllowedByListeners`, and the reason names the problem exactly. With the Kubernetes `Ingress` API, the same situation gives no status at all, only a `404`.

---

## Items 13 And 14: Traffic Through The New Gateway

> **Task item 13:** `GET /book` with `Host: booking.ica.local` returns **200** through the new gateway.
>
> **Task item 14:** `GET /items` with `Host: catalog.ica.local` returns **200** through the same gateway.

Start a port forward to the Service of the new gateway, not to `istio-ingressgateway`. `istio-ingressgateway` is the proxy for the own `Gateway` object of Istio, and it has no configuration for these routes. Then send one request for each host:

```sh
kubectl -n gwapi-demo port-forward svc/shared-gateway-istio 8080:80 >/dev/null 2>&1 &
sleep 4
for request in "booking.ica.local /book" "catalog.ica.local /items"; do
  read -r host uri <<< "$request"
  printf '%-20s %-8s -> ' "$host" "$uri"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $host" "http://localhost:8080$uri"
done
```

```text
booking.ica.local    /book    -> 200
catalog.ica.local    /items   -> 200
```

Both requests return `200`. Two namespaces now share one gateway. The platform team owns the `Gateway` and granted access to each namespace with a label. Stop the port forward with `kill %1` when you are done.

---

## Item 12: The Team Namespace Carries The Label

> **Task item 12:** The `gwapi-team` namespace carries the label `gateway-access=true`.

The label listing in item 4 shows `gateway-access=true` on `gwapi-team`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-01
```

The grader reads the status of the `Gateway` and both routes, and sends requests through the new gateway.

---

## Mistakes That Fail The Grader

- **Forgetting a namespace label (items 4 and 10).** The route of that namespace reports `Accepted=False (NotAllowedByListeners)`. Read the status rather than guessing.
- **`from: All` (item 3).** The traffic flows, but the task asks for `Selector`.
- **Leaving out `namespace` in the cross-namespace `parentRefs` (items 6 and 11).** The route looks for the `Gateway` in its own namespace and finds nothing.
- **Port-forwarding to `istio-ingressgateway` (items 13 and 14).** That is the proxy for the own `Gateway` object of Istio, and it has no configuration for these routes.
- **Setting `hostname` on the listener (item 2).** The task asks for none, so the listener accepts any host and the routes decide.
- **Looking for the proxy in `istio-system` (item 8).** It is `shared-gateway-istio` in `gwapi-demo`.
- **Using `networking.istio.io/v1` (item 1).** That is the wrong API group: the own `Gateway` of Istio has a `selector` and configures a proxy pod that already runs.
- **Reading `PathPrefix` as a text prefix (items 5 and 6).** It matches whole path segments, like the `Ingress` path type `Prefix` and unlike `uri.prefix` of Istio.
