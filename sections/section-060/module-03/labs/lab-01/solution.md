# Solution Walkthrough

The solution is three objects and two namespace labels. The labels are what let the route from the other namespace attach. If you forget one, the Gateway API reports the failure clearly in the route's status.

## Step 1: Confirm the Prerequisites

Check that the CRDs and the `istio` class exist, that neither namespace has the `gateway-access` label yet, and that no `Gateway` or `HTTPRoute` exists:

```sh
kubectl get crd | grep gateway.networking.k8s.io
kubectl get gatewayclass
kubectl get ns gwapi-demo gwapi-team --show-labels
kubectl -n gwapi-demo get gateway,httproute
```

```text
gatewayclasses.gateway.networking.k8s.io   2026-09-27T09:12:00Z
gateways.gateway.networking.k8s.io         2026-09-27T09:12:00Z
httproutes.gateway.networking.k8s.io       2026-09-27T09:12:00Z
NAME    CONTROLLER                    ACCEPTED   AGE
istio   istio.io/gateway-controller   True       8m
NAME         STATUS   AGE   LABELS
gwapi-demo   Active   8m    istio-injection=enabled,kubernetes.io/metadata.name=gwapi-demo
gwapi-team   Active   8m    istio-injection=enabled,kubernetes.io/metadata.name=gwapi-team
No resources found in gwapi-demo namespace.
```

The CRDs are present, the `GatewayClass` is accepted, and neither namespace carries `gateway-access` yet. The controller name is `istio.io/gateway-controller`. It is a different name from `istio.io/ingress-controller`, the controller for the older Kubernetes `Ingress` object: the two APIs have separate controllers.

## Step 2: Create the Gateway

Write each manifest to a file and apply the file. This is a good exam habit: you can read the file again, edit it and apply it again, while a heredoc is gone as soon as it runs.

Save this as `gateway-shared-gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gwapi-demo
  annotations:
    # kind has no load balancer: without this the Gateway's Service sits at
    # EXTERNAL-IP <pending> and the Gateway reports Programmed=False.
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

Then check the result:

```sh
kubectl -n gwapi-demo rollout status deployment shared-gateway-istio --timeout=120s
kubectl -n gwapi-demo get deploy,svc -l gateway.networking.k8s.io/gateway-name=shared-gateway
```

```text
gateway.networking.k8s.io/shared-gateway created
deployment "shared-gateway-istio" successfully rolled out
NAME                                   READY   AGE
deployment.apps/shared-gateway-istio   1/1     28s
NAME                           TYPE           PORT(S)        AGE
service/shared-gateway-istio   LoadBalancer   80:31380/TCP   28s
```

You created one object, and Istio created a Deployment and a Service **in `gwapi-demo`**. Confirm that nothing for this `Gateway` appeared in `istio-system`:

```sh
kubectl -n istio-system get deploy | grep shared || echo "(nothing - correct)"
```

```text
(nothing - correct)
```

Three details in the YAML matter:

- **No `selector`.** The Gateway API uses `gatewayClassName` instead; Istio creates the proxy rather than finding one.
- **No `hostname` on the listener.** The task asks for a listener that accepts any host, so the routes decide by their `hostnames`.
- **`from: Selector`**, not `All`. `All` would let the traffic through but fails the task: the point is a deliberate grant that you can take back.

## Step 3: Label Both Namespaces

Give both namespaces the label that the `allowedRoutes` selector matches:

```sh
kubectl label namespace gwapi-team gateway-access=true
kubectl label namespace gwapi-demo gateway-access=true
```

```text
namespace/gwapi-team labeled
namespace/gwapi-demo labeled
```

The labels are the grant. Without them the selector matches nothing, and the
route from `gwapi-team` cannot attach. Its status then says exactly that.

The second line is the one people miss. A `Selector` allows only the
namespaces whose labels match, and the `Gateway`'s **own** namespace is not an
exception. If you label only `gwapi-team`, the route from `gwapi-team` attaches
while the route right next to the `Gateway` is refused.

## Step 4: The Same-Namespace Route

The `booking` route lives next to the `Gateway` in `gwapi-demo`. Save this as `httproute-booking.yaml`:

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

This route needs no `namespace` in `parentRefs`: the route and the `Gateway` are both in `gwapi-demo`.

## Step 5: The Cross-Namespace Route

The `catalog` route lives in `gwapi-team` and points at the `Gateway` in `gwapi-demo`. Save this as `httproute-catalog.yaml`:

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

**`namespace: gwapi-demo` in `parentRefs` is required here.** Without it, the route looks for a `Gateway` called `shared-gateway` in its own namespace, `gwapi-team`, where none exists.

The `backendRefs` entry has no namespace, because the backend is in the route's own namespace, which is the normal case. A route that sends to a Service in another namespace also needs a `ReferenceGrant` in that namespace: a Gateway API object that allows references from another namespace. It is the same deny-by-default idea, applied to backends.

## Step 6: Read the Status Conditions

The Gateway API reports what is wrong in the status of each object. This is its biggest practical advantage over the Kubernetes `Ingress` API:

```sh
kubectl -n gwapi-demo get gateway shared-gateway \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
for r in gwapi-demo/booking gwapi-team/catalog; do
  ns=${r%%/*}; name=${r##*/}
  printf '%-22s ' "$r"
  kubectl -n "$ns" get httproute "$name" \
    -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}{"\n"}'
done
```

```text
Accepted=True Programmed=True
gwapi-demo/booking     Accepted=True ResolvedRefs=True
gwapi-team/catalog     Accepted=True ResolvedRefs=True
```

Six `True` values mean the whole chain works. It is worth seeing the failure once. Remove the label from `gwapi-team`, read the route's conditions, and put the label back:

```sh
kubectl label namespace gwapi-team gateway-access-
sleep 3
kubectl -n gwapi-team get httproute catalog \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} ({.reason}) {end}{"\n"}'
kubectl label namespace gwapi-team gateway-access=true
```

```text
Accepted=False (NotAllowedByListeners)
```

The reason `NotAllowedByListeners` names the problem exactly, in the route's own status. With the Kubernetes `Ingress` API, the same situation gives no status at all, only a `404`.

## Step 7: Verify Traffic

Start a port forward to the Service of the **new** gateway, not to `istio-ingressgateway`, and send one request for each host:

```sh
kubectl -n gwapi-demo port-forward svc/shared-gateway-istio 8080:80 >/dev/null 2>&1 &
sleep 3
for t in "booking.ica.local /book" "catalog.ica.local /items"; do
  set -- $t
  printf '%-20s %-8s -> ' "$1" "$2"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $1" "http://localhost:8080$2"
done
```

```text
booking.ica.local    /book    -> 200
catalog.ica.local    /items   -> 200
```

Two namespaces now share one gateway. The platform team owns the `Gateway` and granted access to each namespace with a label.

## Common Mistakes

- **Forgetting the namespace label.** The route from the other namespace reports `Accepted=False (NotAllowedByListeners)`. Read the status rather than guessing.
- **`from: All`.** Works, and fails the task. The grader checks for `Selector`.
- **Omitting `namespace` in the cross-namespace `parentRefs`.** The route looks for the Gateway in its own namespace and finds nothing.
- **Port-forwarding to `istio-ingressgateway`.** That is the proxy for Istio's own `Gateway` object, and it has no configuration for these routes.
- **Setting `hostname` on the listener.** The task asks for none, so the listener accepts any host and the routes discriminate.
- **Looking for the proxy in `istio-system`.** It is `shared-gateway-istio` in `gwapi-demo`.
- **Using `networking.istio.io/v1`.** That is the wrong API group: Istio's own `Gateway` has a `selector` and configures a proxy pod that already runs.
- **Reading `PathPrefix` as a text prefix.** It matches whole path segments, like the `Ingress` path type `Prefix` and unlike Istio's `uri.prefix`.
