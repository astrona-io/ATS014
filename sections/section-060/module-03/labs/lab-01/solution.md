# Solution Walkthrough

Four objects and a namespace label. The label is the part that makes the cross-namespace route work, and forgetting it produces the one failure this API reports clearly.

---

## Step 1: Confirm the Prerequisites

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

CRDs present, `GatewayClass` accepted, neither namespace carries `gateway-access` yet. Note the controller string is `istio.io/gateway-**controller**` — different from module 2's `istio.io/ingress-controller`. Separate APIs, separate controllers.

---

## Step 2: Create the Gateway

```sh
kubectl apply -f - <<'EOF'
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
EOF
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

One object created, and Istio created a Deployment and a Service **in `gwapi-demo`**. Confirm nothing appeared in `istio-system`:

```sh
kubectl -n istio-system get deploy | grep shared || echo "(nothing - correct)"
```

```text
(nothing - correct)
```

Three details in the YAML:

- **No `selector`.** This API has `gatewayClassName` instead; the proxy is created rather than found.
- **No `hostname` on the listener.** The task asks for it to accept any host, so the routes decide by `hostnames`.
- **`from: Selector`**, not `All`. `All` would work for traffic and fails the task — the point is a deliberate, revocable grant.

---

## Step 3: Label Both Namespaces

```sh
kubectl label namespace gwapi-team gateway-access=true
kubectl label namespace gwapi-demo gateway-access=true
```

```text
namespace/gwapi-team labeled
namespace/gwapi-demo labeled
```

This is the grant. Without it the selector matches nothing, and the
cross-namespace route in step 5 will attach to nothing — reporting exactly that
in its status.

The second line is the one people miss. A `Selector` grant is literal: it
permits the namespaces whose labels match, and the Gateway's **own** namespace
gets no exemption. Label only `gwapi-team` and you get the confusing result that
the cross-namespace route attaches while the route sitting right beside the
Gateway is rejected.

---

## Step 4: The Same-Namespace Route

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

No `namespace` in `parentRefs` is needed — the route and the Gateway are both in `gwapi-demo`.

---

## Step 5: The Cross-Namespace Route

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

**`namespace: gwapi-demo` in `parentRefs` is required here.** Without it the route looks for a `Gateway` called `shared-gateway` in its own namespace, `gwapi-team`, where none exists.

Note the `backendRefs` has no namespace — the backend is in the route's own namespace, which is the normal case. Referring to a Service in a *third* namespace would additionally need a `ReferenceGrant`, which is the same deny-by-default idea applied to backends.

---

## Step 6: Read the Status Conditions

This API tells you what is wrong, which is its biggest practical advantage over `Ingress`:

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

Six `True` values is the whole chain working. Worth trying the failure once:

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

`NotAllowedByListeners` — named precisely, in the route's own status. With `Ingress` this situation produces silence and a 404.

---

## Step 7: Verify Traffic

Port-forward to the **new** gateway, not to `istio-ingressgateway`:

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

Two namespaces, two teams, one shared gateway that the platform team owns and explicitly granted access to.

---

## Common Mistakes

- **Forgetting the namespace label.** The cross-namespace route reports `Accepted=False (NotAllowedByListeners)` — read the status rather than guessing.
- **`from: All`.** Works, and fails the task. The grader checks for `Selector`.
- **Omitting `namespace` in the cross-namespace `parentRefs`.** The route looks for the Gateway in its own namespace and finds nothing.
- **Port-forwarding to `istio-ingressgateway`.** That is module 1's proxy; it knows nothing about these routes.
- **Setting `hostname` on the listener.** The task asks for none, so the listener accepts any host and the routes discriminate.
- **Looking for the proxy in `istio-system`.** It is `shared-gateway-istio` in `gwapi-demo`.
- **Using `networking.istio.io/v1`.** Wrong API group entirely — that object has a `selector` and configures an existing pod.
- **Reading `PathPrefix` as a string prefix.** It is element-wise, like `Ingress` and unlike Istio's `uri.prefix`.
