# Solution Walkthrough

The `HTTPRoute` was correct from the start. It names a `Gateway` that does not exist, so it cannot attach anywhere, and no gateway proxy exists to carry the requests. The fix is one `Gateway` object that matches the route. The Gateway API is the Kubernetes API for gateways and routes: a `Gateway` opens listeners, and an `HTTPRoute` holds the routing rules. The Start section shows what is missing. Items 1 to 4 create the `Gateway`, and items 5 to 10 prove the result.

---

## Start: Confirm What Is Missing

The task says that the `Gateway` was never created, and that `istio-system` holds only `istiod`. List the `Gateway` and `HTTPRoute` objects of the namespace, read the status of the route, and send one request to the address where the gateway will be. Then save the state that item 10 must keep:

```sh
kubectl -n starfleet get gateway,httproute
kubectl -n starfleet get httproute bridge -o jsonpath='{.status.parents}{"\n"}'
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl -n istio-system get deploy
kubectl -n starfleet get httproute bridge -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
NAME                                         HOSTNAMES                   AGE
httproute.gateway.networking.k8s.io/bridge   ["starfleet.example.com"]   0s
[]
000
command terminated with exit code 6
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
istiod   1/1     1            1           54s
generation=1 uid=e64c4f9b-2806-45df-9b51-476bbd2ed25a
{"hostnames":["starfleet.example.com"],"parentRefs":[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"starfleet-gateway"}],"rules":[{"backendRefs":[{"group":"","kind":"Service","name":"bridge","port":9080,"weight":1}],"matches":[{"path":{"type":"PathPrefix","value":"/productpage"}}]}]}
NAME        UID
bridge-v1   3f1a75b4-47fa-4270-b6d3-3d5b69a943dd
cargo-v1    78387afc-5201-44c6-a37b-880651934cf5
navcom-v1   6cefb9ac-4e41-43b0-bbdf-7c06c52689ab
scout-v1    0ff4fed3-15de-4b99-a848-e46f4b189679
scout-v2    588cc176-de90-4728-b526-fdd38a71493d
scout-v3    305842aa-9021-4d8a-8c5d-410a6a3864c9
shuttle     0967b6d5-ad19-48b5-902c-b5a74584f458
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

There is a route but no `Gateway`. The list of parent gateways in `status.parents` is empty: no controller wrote a status for the route, so it has no `Accepted` condition or any other. The request fails before it starts. `curl` exit code `6` means that DNS could not resolve the host name, because the Service `starfleet-gateway-istio` does not exist yet. Read the `spec` of the route in the last command. It tells you what the `Gateway` must look like: a `Gateway` named `starfleet-gateway` in the namespace of the route (the `parentRefs` entry has no `namespace`), with a listener that serves `starfleet.example.com`. The Kubernetes API server filled in the default values `group`, `kind` and `weight: 1`.

---

## Items 1 To 4: Create The `Gateway`

> **Task item 1:** A Gateway API `Gateway` named **`starfleet-gateway`** exists in namespace **`starfleet`**, with `gatewayClassName` **`istio`**.
>
> **Task item 2:** It carries the annotation **`networking.istio.io/service-type: ClusterIP`**. This cluster is `kind`, which has no load balancer, so without the annotation the gateway's Service never gets an address.
>
> **Task item 3:** It has exactly **one** listener, named **`http`**, on **port 80**, protocol **`HTTP`**, for the host name **`starfleet.example.com`**.
>
> **Task item 4:** Only routes from the `Gateway`'s own namespace may attach. Keep `allowedRoutes` at **`from: Same`** (or leave it out, which means the same).

The four items describe one object, so you write it once. Save this as `gateway-starfleet.yaml`:

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

```text
gateway.gateway.networking.k8s.io/starfleet-gateway created
```

Wait until Istio has built the gateway and its proxy runs. Then check items 1 to 4. Print the class, the annotation, and the listeners:

```sh
kubectl -n starfleet wait --for=condition=Programmed gateway/starfleet-gateway --timeout=120s
kubectl -n starfleet rollout status deploy/starfleet-gateway-istio --timeout=120s
kubectl -n starfleet get gateway
kubectl -n starfleet get gateway starfleet-gateway \
  -o jsonpath='{.spec.gatewayClassName} {.metadata.annotations.networking\.istio\.io/service-type}{"\n"}{.spec.listeners}{"\n"}'
```

```text
gateway.gateway.networking.k8s.io/starfleet-gateway condition met
Waiting for deployment "starfleet-gateway-istio" rollout to finish: 0 of 1 updated replicas are available...
deployment "starfleet-gateway-istio" successfully rolled out
NAME                CLASS   ADDRESS                                               PROGRAMMED   AGE
starfleet-gateway   istio   starfleet-gateway-istio.starfleet.svc.cluster.local   True         2s
istio ClusterIP
[{"allowedRoutes":{"namespaces":{"from":"Same"}},"hostname":"starfleet.example.com","name":"http","port":80,"protocol":"HTTP"}]
```

The `Gateway` has the class `istio` and the annotation `ClusterIP`. It has exactly one listener, named `http`, on port 80 with the protocol `HTTP`, for the host `starfleet.example.com`, and `allowedRoutes` is `from: Same`.

---

## Item 5: Istio Deployed The Proxy Next To The `Gateway`

> **Task item 5:** Istio deployed the gateway's proxy: a Deployment and a Service named **`starfleet-gateway-istio`** in **`starfleet`**, with a ready pod. `istio-system` still holds only `istiod`.

Istio labels every object that it creates for the `Gateway` with `gateway.networking.k8s.io/gateway-name`. List them, and list `istio-system` for comparison:

```sh
kubectl -n starfleet get deploy,svc -l gateway.networking.k8s.io/gateway-name=starfleet-gateway
kubectl -n istio-system get deploy
```

```text
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/starfleet-gateway-istio   1/1     1            1           2s

NAME                              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)            AGE
service/starfleet-gateway-istio   ClusterIP   10.96.197.191   <none>        15021/TCP,80/TCP   2s
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
istiod   1/1     1            1           56s
```

Istio created the Deployment and the Service in the `starfleet` namespace, next to the `Gateway`. The Deployment has one ready pod. The Service type is `ClusterIP` because of the annotation. `istio-system` still holds only `istiod`.

---

## Item 6: The `Gateway` Is Accepted And Programmed

> **Task item 6:** The `Gateway` reports **`Accepted=True`** and **`Programmed=True`**.

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
```

```text
Accepted=True Programmed=True 
```

---

## Item 7: The Route Is Attached

> **Task item 7:** The `HTTPRoute` `bridge` reports **`Accepted=True`** and **`ResolvedRefs=True`** for this `Gateway`.

Now that the `Gateway` exists, its controller writes a status for the route:

```sh
sleep 3
kubectl -n starfleet get httproute bridge \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

The gateway accepted the route (`Accepted`), and the `bridge` Service exists (`ResolvedRefs`). Before you created the `Gateway`, the status was an empty list.

---

## Items 8 And 9: Requests Through The Gateway

> **Task item 8:** 10 out of 10 requests sent from the `shuttle` pod to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.
>
> **Task item 9:** A request to the same address with **`Host: other.example.com`** returns **`404`**.

Send 10 requests with the host of the listener, and one request with another host:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
done | sort | uniq -c
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: other.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
  10 200
404
```

All 10 requests for `starfleet.example.com` reach the `bridge` Service. The request for another host gets `404` from the gateway proxy, because the listener serves only its own host name. If the first requests get `503`, the new proxy has not received its first configuration from `istiod`, the Istio control plane. Wait a few seconds and send them again.

---

## Item 10: Nothing Else Changed

> **Task item 10:** The `HTTPRoute` `bridge` is **left unchanged**. Leave the Deployments and Services of the app unchanged too.

Run the three commands from the Start section that print the route, the Deployments and the Services:

```sh
kubectl -n starfleet get httproute bridge -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
generation=1 uid=e64c4f9b-2806-45df-9b51-476bbd2ed25a
{"hostnames":["starfleet.example.com"],"parentRefs":[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"starfleet-gateway"}],"rules":[{"backendRefs":[{"group":"","kind":"Service","name":"bridge","port":9080,"weight":1}],"matches":[{"path":{"type":"PathPrefix","value":"/productpage"}}]}]}
NAME                      UID
bridge-v1                 3f1a75b4-47fa-4270-b6d3-3d5b69a943dd
cargo-v1                  78387afc-5201-44c6-a37b-880651934cf5
navcom-v1                 6cefb9ac-4e41-43b0-bbdf-7c06c52689ab
scout-v1                  0ff4fed3-15de-4b99-a848-e46f4b189679
scout-v2                  588cc176-de90-4728-b526-fdd38a71493d
scout-v3                  305842aa-9021-4d8a-8c5d-410a6a3864c9
shuttle                   0967b6d5-ad19-48b5-902c-b5a74584f458
starfleet-gateway-istio   663867d5-67ef-4770-9d55-5228b4fc1854
NAME                      PORT
bridge                    9080
cargo                     9080
navcom                    9080
scout                     9080
starfleet-gateway-istio   15021
```

The route has the same `generation` and the same spec. The app Deployments and Services have the same `UID` values and ports. The only new objects are the Deployment and the Service of the gateway, which Istio created for the `Gateway`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-02
```

The grader reads the status of both objects and sends real requests through the gateway from the `shuttle` pod.

---

## Mistakes That Fail The Grader

- **A different name or namespace for the `Gateway` (item 1).** The route names `starfleet-gateway` in its own namespace. Any other name leaves its status empty.
- **Leaving out the annotation `networking.istio.io/service-type: ClusterIP` (item 2).** The Service becomes a `LoadBalancer` that never gets an address on `kind`, and the `Gateway` stays `Programmed=False`.
- **A listener without `hostname`, or with a different one (items 3 and 9).** The task asks for exactly `starfleet.example.com`.
- **`allowedRoutes` set to `All` or `Selector` (item 4).** The route lives in the namespace of the `Gateway`, so `Same` is all it needs.
- **Editing the `HTTPRoute` to match a different `Gateway` (item 10).** The route was correct. Create the `Gateway` to match it.
- **Installing an Istio ingress gateway in `istio-system` (item 5).** The Gateway API builds the proxy for you, next to the `Gateway`.
- **Deleting and re-creating the `Gateway` within a few seconds (item 6).** It can stay `Programmed=False` with `AddressNotAssigned`. Delete it, wait half a minute, and apply it again.
