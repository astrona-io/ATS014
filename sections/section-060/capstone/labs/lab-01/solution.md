# Solution Walkthrough

The solution is seven objects across three APIs, plus one secret. Build them in order and check each one before you move on: a mistake in one API does not show up in the others.

## Step 1: Confirm All Three APIs Are Available

Check that the shared ingress gateway runs, that Istio's `GatewayClass` exists, and that nothing is configured yet:

```sh
kubectl -n istio-system get deploy istio-ingressgateway
kubectl get gatewayclass
kubectl get ingressclass
kubectl -n edge get gateway.networking.istio.io,virtualservice,ingress,httproute
```

```text
NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
istio-ingressgateway   1/1     1            1           25s
NAME           CONTROLLER                    ACCEPTED   AGE
istio          istio.io/gateway-controller   True       29s
istio-remote   istio.io/unmanaged-gateway    True       29s
No resources found
No resources found in edge namespace.
```

The shared ingress gateway is running, Istio's `istio` `GatewayClass` is registered (`istio-remote` is a second class that this task does not use), there is no `IngressClass` yet, and nothing is configured.

## Step 2: A, Istio's Own Objects

Write each manifest to a file and apply the file. This is a good exam habit: you can read the file again, edit it and apply it again, while a heredoc is gone as soon as it runs.

Istio's own `Gateway` opens port 80 on the existing `istio-ingressgateway` proxy. Save this as `gateway-native-gw.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f gateway-native-gw.yaml
```

The `VirtualService` binds the route to that `Gateway`. Save this as `virtualservice-native.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-native.yaml
```

The `selector` finds the **existing** `istio-ingressgateway` pod, and `gateways: [native-gw]` attaches the routes to it. Leaving out the `gateways` field is the most common failure.

## Step 3: B, The Kubernetes Ingress API

An `IngressClass` tells Kubernetes which controller serves an `Ingress`. Save this as `ingressclass-istio.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Apply it:

```sh
kubectl apply -f ingressclass-istio.yaml
```

The `Ingress` uses that class and names the TLS secret. Save this as `ingress-legacy.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f ingress-legacy.yaml
```

Then create the TLS secret in `istio-system`, from the certificate and key the lab provides:

```sh
kubectl -n istio-system create secret tls legacy-credential \
  --key=/tmp/legacy.key --cert=/tmp/legacy.crt
```

Two controller names are in use now, and they are different:

| API | Controller |
| --- | --- |
| Kubernetes `Ingress` | `istio.io/ingress-controller` |
| Gateway API | `istio.io/gateway-controller` |

The secret goes in **`istio-system`**, because the gateway pod that reads it runs there, and it can read secrets only from its own namespace. This `Ingress` and Istio's `Gateway` above are both served by the *same* `istio-ingressgateway` pod: two APIs, one data plane.

## Step 4: C, The Kubernetes Gateway API

The Gateway API `Gateway` makes Istio deploy a new proxy in `edge`. Save this as `gateway-modern-gw.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: modern-gw
  namespace: edge
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
```

Apply it:

```sh
kubectl apply -f gateway-modern-gw.yaml
```

The `HTTPRoute` attaches to that `Gateway`. Save this as `httproute-modern.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f httproute-modern.yaml
```

Then check the result:

```sh
kubectl -n edge rollout status deployment modern-gw-istio --timeout=120s
kubectl -n edge get deploy,svc | grep modern-gw
```

```text
deployment "modern-gw-istio" successfully rolled out
deployment.apps/modern-gw-istio   1/1     1            1           18s
service/modern-gw-istio   ClusterIP   10.96.132.189   <none>        15021/TCP,80/TCP   18s
```

The Service has type `ClusterIP` because of the `networking.istio.io/service-type` annotation. Without it, Istio creates a `LoadBalancer` Service that stays at `<pending>` on `kind`.

This is the difference worth seeing side by side: `native-gw` configured an existing pod in `istio-system`, and `modern-gw` **created a new pod in `edge`**. The two `Gateway` kinds share a name and behave in completely different ways.

No `allowedRoutes` is needed: the route is in the same namespace as the `Gateway`, and `Same` is the default.

## Step 5: Check the Status Conditions

Only the Gateway API objects report status conditions. The other two APIs have nothing like them, which is itself a difference between the APIs.

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

## Step 6: Verify All Three, Through Two Different Proxies

Start three port forwards, two to the shared ingress gateway and one to the new gateway, and send one request for each host. The last request sends the `modern.ica.local` host to the shared gateway on purpose:

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

The last line proves the point. `modern.ica.local` works on port 8081 and gets `404` on port 8080, because those are two different proxy pods with two different route tables. The Gateway API object did not extend the shared gateway; Istio deployed a new one for it.

Confirm it from the route tables of both proxies:

```sh
echo "--- shared gateway ---"
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -E 'native|legacy|modern'
echo "--- modern gateway ---"
istioctl proxy-config routes deploy/modern-gw-istio -n edge | grep -E 'native|legacy|modern'
```

```text
--- shared gateway ---
http.8080                                                                                              legacy.ica.local:80      legacy.ica.local     PathPrefix:/api        legacy-ica-local-legacy-istio-autogenerated-k8s-ingress.edge
http.8080                                                                                              native.ica.local:80      native.ica.local     /api*                  native.edge
https.443.https-443-ingress-legacy-edge-0.legacy-istio-autogenerated-k8s-ingress-edge.istio-system     legacy.ica.local:443     legacy.ica.local     PathPrefix:/api        legacy-ica-local-legacy-istio-autogenerated-k8s-ingress.edge
--- modern gateway ---
http.80     modern.ica.local:80     modern.ica.local     PathPrefix:/api        edge~modern-gw~istio-autogenerated-k8s-gateway~http~modern.ica.local.edge
```

The columns are `NAME`, `VHOST NAME`, `DOMAINS`, `MATCH` and `VIRTUAL SERVICE`; `grep` removed the header lines. One proxy holds two hosts, and the other holds one. The entries on the shared gateway came from two *different* APIs: `native.edge` is your `VirtualService`, and the names that end in `istio-autogenerated-k8s-ingress` are the configuration `istiod` generated from the `Ingress`. The `Ingress` serves `legacy.ica.local` on both port 80 and port 443. The `MATCH` column also shows the two kinds of prefix: `/api*` for the `VirtualService`, which compares characters, and `PathPrefix:/api` for the `Ingress` and the `HTTPRoute`, which compare whole path elements.

## Common Mistakes

- **Mixing up the two controller names.** `istio.io/ingress-controller` for `IngressClass`, `istio.io/gateway-controller` for `GatewayClass`.
- **Mixing up the two `Gateway` kinds.** Check the `apiVersion`: `networking.istio.io` has a `selector`, and `gateway.networking.k8s.io` has a `gatewayClassName`.
- **The TLS secret in `edge`.** The HTTPS listener never comes up and reports no error, while HTTP keeps working.
- **Leaving out `gateways:` on the `VirtualService`.** The routes apply only to `mesh`, the sidecars inside the mesh, and the gateway answers `404`.
- **Port-forwarding to the wrong proxy.** `modern.ica.local` is only on `modern-gw-istio`.
- **Adding an Istio `Gateway` for `modern.ica.local` "to be safe".** The shared gateway would then serve that host too, and the grader checks that it does not.
- **Using `pathType: Exact` on the Ingress.** Only `/api` itself would match, not the paths below it, so the route no longer behaves as a prefix.
