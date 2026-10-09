# Solution Walkthrough

The `HTTPRoute` was correct from the start. It named a `Gateway` that did not exist, so it could not attach anywhere, and no gateway proxy existed to carry the requests. The fix is one `Gateway` object that matches the route.

## Step 1: Confirm what is missing

List the `Gateway` and `HTTPRoute` objects in the namespace, and read the route's status:

```sh
kubectl get gateway,httproute -n starfleet
kubectl get httproute bridge -n starfleet -o jsonpath='{.status.parents}{"\n"}'
```

```text
NAME                                         HOSTNAMES                   AGE
httproute.gateway.networking.k8s.io/bridge   ["starfleet.example.com"]   6s
[]
```

There is a route but no `Gateway`. The route's list of parent gateways in `status.parents` is empty: no controller wrote a status for the route, so it has no `Accepted` condition or any other. A request to the gateway's address fails before it starts, because the Service `starfleet-gateway-istio` does not exist yet:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
000
command terminated with exit code 6
```

`curl` exit code `6` means that DNS could not resolve the host name. There is no gateway Service to send the request to.

## Step 2: Read what the route expects

The `Gateway` must match the route, so read the route's `spec`:

```sh
kubectl get httproute bridge -n starfleet -o yaml
```

The important part (the output is shortened):

```text
spec:
  hostnames:
  - starfleet.example.com
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: starfleet-gateway
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: bridge
      port: 9080
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /productpage
```

The route needs a `Gateway` named `starfleet-gateway` in its own namespace (the `parentRefs` entry has no `namespace`), with a listener that serves `starfleet.example.com`. The Kubernetes API server filled in the default values `group`, `kind` and `weight: 1`.

## Step 3: Create the Gateway

Save this as `gateway-starfleet.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: starfleet.example.com
    allowedRoutes:
      namespaces:
        from: Same
```

Apply it:

```sh
kubectl apply -f gateway-starfleet.yaml
```

Then check the result. Wait until Istio has built the gateway and its proxy runs:

```sh
kubectl wait -n starfleet --for=condition=Programmed gateway/starfleet-gateway --timeout=120s
kubectl rollout status deploy/starfleet-gateway-istio -n starfleet --timeout=120s
kubectl get gateway -n starfleet
```

```text
gateway.gateway.networking.k8s.io/starfleet-gateway condition met
Waiting for deployment "starfleet-gateway-istio" rollout to finish: 0 of 1 updated replicas are available...
deployment "starfleet-gateway-istio" successfully rolled out
NAME                CLASS   ADDRESS                                               PROGRAMMED   AGE
starfleet-gateway   istio   starfleet-gateway-istio.starfleet.svc.cluster.local   True         1s
```

## Step 4: Check where Istio deployed the proxy

Istio labels every object it creates for the `Gateway` with `gateway.networking.k8s.io/gateway-name`. List them, and list `istio-system` for comparison:

```sh
kubectl get deploy,svc -n starfleet -l gateway.networking.k8s.io/gateway-name=starfleet-gateway
kubectl get deploy -n istio-system
```

```text
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/starfleet-gateway-istio   1/1     1            1           1s

NAME                              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)            AGE
service/starfleet-gateway-istio   ClusterIP   10.96.12.131   <none>        15021/TCP,80/TCP   1s
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
istiod   1/1     1            1           79s
```

Istio created the Deployment and the Service in the `starfleet` namespace, next to the `Gateway`. The Service type is `ClusterIP` because of the annotation. `istio-system` still holds only `istiod`.

## Step 5: Read the route's status again

Now that the `Gateway` exists, its controller writes a status for the route:

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

The gateway accepted the route (`Accepted`), and the `bridge` Service exists (`ResolvedRefs`).

## Step 6: Send requests through the gateway

Send one request with the listener's host name, and one with another host name:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: other.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
200
404
```

Requests for `starfleet.example.com` reach the `bridge` Service. Requests for any other host get `404` from the gateway proxy, because the listener only serves its own host name. If the first request gets `503`, the new proxy has not received its first configuration from `istiod` yet: wait a few seconds and send it again.

## Mistakes that fail the grader

- **A different name or namespace for the `Gateway`.** The route names `starfleet-gateway` in its own namespace. Any other name leaves its status empty.
- **Leaving out the `networking.istio.io/service-type: ClusterIP` annotation.** The Service becomes a `LoadBalancer` that never gets an address on `kind`, and the `Gateway` stays `Programmed=False`.
- **A listener without `hostname`, or with a different one.** The task asks for exactly `starfleet.example.com`, so other hosts get `404`.
- **`allowedRoutes` set to `All` or `Selector`.** The route lives in the `Gateway`'s own namespace, so `Same` is all it needs.
- **Editing the `HTTPRoute` to match a different `Gateway`.** The route was correct. Create the `Gateway` to match it.
- **Installing an Istio ingress gateway in `istio-system`.** The Gateway API builds the proxy for you, next to the `Gateway`.
- **Deleting and re-creating the `Gateway` within a few seconds.** It can stay `Programmed=False` with `AddressNotAssigned`. Delete it, wait half a minute, and apply it again.
