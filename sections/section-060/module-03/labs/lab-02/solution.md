# Solution Walkthrough

Mission debrief, astronaut. The flight plan was ready all along. It named a gate that nobody had built, so it had nowhere to dock, and no proxy existed to carry the signals.

---

## Step 1: Confirm what is missing

Look for the gate and the route, and read the route's status:

```sh
kubectl get gateway,httproute -n starfleet
kubectl get httproute bridge -n starfleet -o jsonpath='{.status.parents}{"\n"}'
```

```text
NAME                                         HOSTNAMES                   AGE
httproute.gateway.networking.k8s.io/bridge   ["starfleet.example.com"]   6s
[]
```

There is a route but no `Gateway`. The route's list of gates in `status.parents` is empty: no gate answered, so nobody reported `Accepted` or anything else. A signal to the gate's address fails before it starts, because the Service `starfleet-gateway-istio` does not exist yet:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
000
command terminated with exit code 6
```

`curl` exit code `6` means the name could not be found. There is no gate to send the signal to.

## Step 2: Read what the route expects

The gate must fit the route, so read the route's `spec`:

```sh
kubectl get httproute bridge -n starfleet -o yaml
```

The important part (trimmed):

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

The route wants a `Gateway` named `starfleet-gateway` on its own planet (the `parentRefs` entry has no `namespace`), with a listener that serves `starfleet.example.com`. Kubernetes filled in the defaults `group`, `kind` and `weight: 1`.

## Step 3: Build the gate

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

Then wait until the gate is built and its proxy runs:

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

## Step 4: Check where Istio built the proxy

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

Istio built the Deployment and the Service on the `starfleet` planet, next to the `Gateway`. The Service type is `ClusterIP`, thanks to the annotation. `istio-system` still holds only `istiod`.

## Step 5: Read the route's status again

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

The gate now answers for the route: it took the route (`Accepted`), and the `bridge` Service exists (`ResolvedRefs`).

## Step 6: Send signals through the gate

Send one signal with the right host name, and one with another:

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

Signals for `starfleet.example.com` reach the bridge. Signals for any other host get `404` from the gate, because the listener only serves its own host name. If the first signal gets `503`, the new proxy is still waiting for its first orders: wait a few seconds and send it again.

## Mistakes that fail the grader

- **A different name or namespace for the `Gateway`.** The route names `starfleet-gateway` on its own planet. Any other name leaves its status empty.
- **Leaving out the `networking.istio.io/service-type: ClusterIP` annotation.** The Service becomes a `LoadBalancer` that never gets an address on `kind`, and the `Gateway` stays `Programmed=False`.
- **A listener without `hostname`, or with a different one.** The task asks for exactly `starfleet.example.com`, so other hosts get `404`.
- **`allowedRoutes` set to `All` or `Selector`.** The route lives on the gate's own planet, so `Same` is all it needs.
- **Editing the `HTTPRoute` to fit a different gate.** The route was correct. Build the gate to fit it.
- **Installing an Istio ingress gateway in `istio-system`.** The Gateway API builds the proxy for you, next to the `Gateway`.
- **Deleting and re-creating the `Gateway` within a few seconds.** It can stay `Programmed=False` with `AddressNotAssigned`. Delete it, wait half a minute, and apply it again.
