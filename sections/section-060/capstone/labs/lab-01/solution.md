# Solution Walkthrough

Seven objects across three APIs. Build them in order and verify each before moving on — a mistake in one is invisible from the others.

---

## Step 1: Confirm All Three APIs Are Available

```sh
kubectl -n istio-system get deploy istio-ingressgateway
kubectl get gatewayclass
kubectl get ingressclass
kubectl -n edge get gateway.networking.istio.io,virtualservice,ingress,httproute 2>/dev/null
```

```text
NAME                   READY   AGE
istio-ingressgateway   1/1     7m
NAME    CONTROLLER                    ACCEPTED   AGE
istio   istio.io/gateway-controller   True       7m
No resources found
No resources found in edge namespace.
```

The shared gateway is running, Istio's `GatewayClass` is registered, no `IngressClass` yet, and nothing is configured.

---

## Step 2: A — Native Istio Objects

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: native-gw
  namespace: edge
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - native.ica.local
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: native
  namespace: edge
spec:
  hosts:
    - native.ica.local
  gateways:
    - native-gw
  http:
    - match:
        - uri:
            prefix: /api
      route:
        - destination:
            host: native-app
            port:
              number: 80
EOF
```

`selector` finds the **existing** `istio-ingressgateway` pod, and `gateways: [native-gw]` is what attaches the routes to it. Omitting that field is the classic failure.

---

## Step 3: B — Kubernetes Ingress

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy
  namespace: edge
spec:
  ingressClassName: istio
  tls:
    - hosts:
        - legacy.ica.local
      secretName: legacy-credential
  rules:
    - host: legacy.ica.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: legacy-app
                port:
                  number: 80
EOF

kubectl -n istio-system create secret tls legacy-credential \
  --key=/tmp/legacy.key --cert=/tmp/legacy.crt
```

Two controller strings are in play now and they are different:

| API | Controller |
| --- | --- |
| Kubernetes `Ingress` | `istio.io/ingress-controller` |
| Gateway API | `istio.io/gateway-controller` |

And the secret goes in **`istio-system`**, because that is where the pod that reads it lives. This `Ingress` and the native `Gateway` above are both served by the *same* `istio-ingressgateway` pod — two APIs, one data plane.

---

## Step 4: C — Gateway API

```sh
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: modern-gw
  namespace: edge
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: modern
  namespace: edge
spec:
  parentRefs:
    - name: modern-gw
  hostnames:
    - modern.ica.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: modern-app
          port: 80
EOF
kubectl -n edge rollout status deployment modern-gw-istio --timeout=120s
kubectl -n edge get deploy,svc | grep modern-gw
```

```text
deployment "modern-gw-istio" successfully rolled out
deployment.apps/modern-gw-istio   1/1     30s
service/modern-gw-istio           LoadBalancer   80:31421/TCP   30s
```

This is the difference worth seeing side by side: `native-gw` configured an existing pod in `istio-system`, and `modern-gw` **created a new pod in `edge`**. Two `Gateway` kinds, one name, entirely different behaviour.

No `allowedRoutes` is needed — the route is in the same namespace, and `Same` is the default.

---

## Step 5: Check the Status Conditions

Only the Gateway API objects report conditions; the other two APIs have nothing comparable, which is itself a point about them.

```sh
kubectl -n edge get gateway.gateway.networking.k8s.io modern-gw \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
kubectl -n edge get httproute modern \
  -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}{"\n"}'
```

```text
Accepted=True Programmed=True
Accepted=True ResolvedRefs=True
```

---

## Step 6: Verify All Three, Through Two Different Proxies

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
kubectl -n edge        port-forward svc/modern-gw-istio      8081:80  >/dev/null 2>&1 &
sleep 4

printf 'native  (shared, HTTP)  -> '
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: native.ica.local" http://localhost:8080/api
printf 'legacy  (shared, HTTPS) -> '
curl -sk -o /dev/null -w '%{http_code}\n' --resolve legacy.ica.local:8443:127.0.0.1 https://legacy.ica.local:8443/api
printf 'modern  (own proxy)     -> '
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: modern.ica.local" http://localhost:8081/api
printf 'modern via shared       -> '
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: modern.ica.local" http://localhost:8080/api
```

```text
native  (shared, HTTP)  -> 200
legacy  (shared, HTTPS) -> 200
modern  (own proxy)     -> 200
modern via shared       -> 404
```

The last line is the one that proves the point. `modern.ica.local` works on port 8081 and 404s on port 8080, because those are two different proxy pods with two different route tables. The Gateway API object did not extend the shared gateway; it brought its own.

Confirm from the route tables directly:

```sh
echo "--- shared gateway ---"
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -E 'native|legacy|modern'
echo "--- modern gateway ---"
istioctl proxy-config routes deploy/modern-gw-istio -n edge | grep -E 'native|legacy|modern'
```

```text
--- shared gateway ---
http.8080   native.ica.local   /api*   native.edge
https.443   legacy.ica.local   /api*   legacy-app.edge
--- modern gateway ---
http.80     modern.ica.local   /api*   modern.edge
```

Two hosts on one proxy, one host on the other — and note the shared gateway's two entries came from two *different* APIs.

---

## Common Mistakes

- **Mixing the two controller strings.** `istio.io/ingress-controller` for `IngressClass`, `istio.io/gateway-controller` for `GatewayClass`.
- **Mixing the two `Gateway` kinds.** Check `apiVersion` — `networking.istio.io` has a `selector`, `gateway.networking.k8s.io` has a `gatewayClassName`.
- **The TLS secret in `edge`.** HTTPS silently never comes up while HTTP keeps working.
- **Omitting `gateways:` on the native `VirtualService`.** Routes attach to `mesh`; the gateway 404s.
- **Port-forwarding to the wrong proxy.** `modern.ica.local` is only on `modern-gw-istio`.
- **Adding a native `Gateway` for `modern.ica.local` "to be safe".** It would make the shared gateway serve it too, and the grader checks that it does not.
- **Using `pathType: Exact` on the Ingress.** `/api` alone would match and the grader's prefix behaviour would differ.
