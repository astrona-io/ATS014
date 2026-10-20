# Solution Walkthrough

The `Gateway` was correct from the start. Each `HTTPRoute` has one typo: one names a Service that does not exist, and the other names a `Gateway` that does not exist. The status conditions of the routes point at both. An `HTTPRoute` holds routing rules, and a `Gateway` opens the listener that the routes attach to. The Start section finds the two faults. Items 1 to 3 describe the repaired routes, and items 4 to 6 prove the result.

---

## Start: Find The Two Faults

The task says that requests for `bridge` fail and requests for `scout` never find a route. Send one request to each path through the gateway, and read the last two lines of the access log of the gateway proxy. The proxy is the Envoy container that Istio created for the `Gateway`. The log lines are shortened to the first 200 characters:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/reviews/0
sleep 3
kubectl -n starfleet logs deploy/starfleet-gateway-istio --tail=2 | cut -c1-200
```

```text
500
404
[2026-10-20T21:59:34.663Z] "GET /productpage HTTP/1.1" 500 NC cluster_not_found - "-" 0 0 0 - "10.244.0.12" "curl/8.11.1" "f3cc7ce4-9cd2-4dda-a132-0189a80d2218" "starfleet.example.com" "-" - - 10.244.
[2026-10-20T21:59:34.729Z] "GET /reviews/0 HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.12" "curl/8.11.1" "22ab6f95-aa24-48ae-b6a9-cbf8144dce2f" "starfleet.example.com" "-" - - 10.244.0.13
```

There are two different failures. The path `/productpage` gets `500` with the response flag `NC` ("no cluster"). A rule matched, but it points at a destination that the gateway proxy does not know. The path `/reviews/0` gets `404` with the flag `NR` ("no route"). No rule on this gateway matches the request at all.

The status of the `Gateway` counts the routes that are attached to each listener. Compare that count with the routes that exist:

```sh
kubectl -n starfleet get gateway
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.status.listeners[0].attachedRoutes}{"\n"}'
kubectl -n starfleet get httproute
```

```text
NAME                CLASS   ADDRESS                                               PROGRAMMED   AGE
starfleet-gateway   istio   starfleet-gateway-istio.starfleet.svc.cluster.local   True         6s
1
NAME     HOSTNAMES                   AGE
bridge   ["starfleet.example.com"]   4s
scout    ["starfleet.example.com"]   4s
```

The `Gateway` is programmed, and two routes exist, but its listener holds only `1`. One route never attached. Read the status conditions of both routes, and let Istio check the namespace. The output of `istioctl analyze` is filtered to the lines with a message number:

```sh
kubectl -n starfleet get httproute bridge \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl -n starfleet get httproute scout -o jsonpath='{.status.parents}{"\n"}'
istioctl analyze -n starfleet 2>&1 | grep IST
```

```text
Accepted=True Accepted: Route was valid
ResolvedRefs=False BackendNotFound: backend(brigde.starfleet.svc.cluster.local) not found
[]
Warning [IST0107] (Deployment starfleet/starfleet-gateway-istio) Misplaced annotation: networking.istio.io/service-type can only be applied to Gateway
Warning [IST0107] (Pod starfleet/starfleet-gateway-istio-cc6f7bf56-486hn) Misplaced annotation: networking.istio.io/service-type can only be applied to Gateway
Warning [IST0107] (Service starfleet/starfleet-gateway-istio) Misplaced annotation: networking.istio.io/service-type can only be applied to Gateway
Warning [IST0171] (HTTPRoute starfleet/bridge) A condition with a negative status is present: type=ResolvedRefs, reason=BackendNotFound, message=backend(brigde.starfleet.svc.cluster.local) not found.
```

The `bridge` route is attached (`Accepted=True`), but its backend is missing (`ResolvedRefs=False`, `BackendNotFound`). The message names it: `brigde`, a typo. The `scout` route has no status at all. No controller wrote a status for it, so the fault is in its `parentRefs`. The `IST0171` message finds the first fault, and it says nothing about `scout`, because a route with no status has no negative condition to report. The `IST0107` warnings come from the objects that Istio created for the `Gateway`, and they do not matter for this task.

Compare the names with what exists, and save the state that item 6 must keep:

```sh
kubectl -n starfleet get svc
kubectl -n starfleet get httproute bridge -o jsonpath='{.spec.rules[0].backendRefs[0].name}{"\n"}'
kubectl -n starfleet get httproute scout -o jsonpath='{.spec.parentRefs[0].name}{"\n"}'
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)            AGE
bridge                    ClusterIP   10.96.41.188    <none>        9080/TCP           51s
cargo                     ClusterIP   10.96.93.107    <none>        9080/TCP           52s
navcom                    ClusterIP   10.96.149.166   <none>        9080/TCP           51s
scout                     ClusterIP   10.96.167.176   <none>        9080/TCP           51s
starfleet-gateway-istio   ClusterIP   10.96.122.187   <none>        15021/TCP,80/TCP   7s
brigde
starfleet-gate
generation=1 uid=fc2a8392-03f4-4b6f-96b7-cb8fb0d53cd0
{"gatewayClassName":"istio","listeners":[{"allowedRoutes":{"namespaces":{"from":"Same"}},"hostname":"starfleet.example.com","name":"http","port":80,"protocol":"HTTP"}]}
NAME                      UID
bridge-v1                 6459ba28-7fca-4b9a-8ab5-f4c98624ab93
cargo-v1                  e0c0cd8e-64e6-438b-b05e-a51a8e80af13
navcom-v1                 55915f26-5b50-43eb-9185-ed1b971381f7
scout-v1                  467c6e82-b1e5-4685-a57a-654226cbc959
scout-v2                  1c3cf555-1581-4536-8638-a20048a00247
scout-v3                  fed17dca-008f-45cc-98a6-4844c4aa00db
shuttle                   e331545b-2ba0-48df-85d3-be77d57e79b5
starfleet-gateway-istio   45cd9f30-5faf-4589-a1d0-84169a3d4c2f
```

The Service is `bridge`, not `brigde`. The `Gateway` is `starfleet-gateway`, not `starfleet-gate`. Fix the routes, not the app. Do not add a Service called `brigde`, and do not create a second `Gateway`.

---

## Items 1 To 3: Repair Both Routes

> **Task item 1:** Both `HTTPRoute` objects, `bridge` and `scout` in `starfleet`, attach to the `Gateway` **`starfleet-gateway`** and report **`Accepted=True`** and **`ResolvedRefs=True`** for it.
>
> **Task item 2:** The `Gateway`'s listener reports **2** attached routes.
>
> **Task item 3:** Both routes keep their host name **`starfleet.example.com`**, their `PathPrefix` paths (`/productpage` and `/reviews`) and their backend port **`9080`**. `bridge` sends to the **`bridge`** Service, and `scout` to the **`scout`** Service.

The `bridge` route needs one change: the backend name. Save this as `httproute-bridge.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bridge
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gateway
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /productpage
    backendRefs:
    - name: bridge
      port: 9080
```

Apply it, and read the conditions and the answer of the gateway:

```sh
kubectl apply -f httproute-bridge.yaml
sleep 6
kubectl -n starfleet get httproute bridge \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
httproute.gateway.networking.k8s.io/bridge configured
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
200
```

The `scout` route needs one change too: the name in `parentRefs`. Save this as `httproute-scout.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: scout
  namespace: starfleet
spec:
  parentRefs:
  - name: starfleet-gateway
  hostnames:
  - starfleet.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /reviews
    backendRefs:
    - name: scout
      port: 9080
```

Apply it, and read the conditions:

```sh
kubectl apply -f httproute-scout.yaml
sleep 6
kubectl -n starfleet get httproute scout \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

```text
httproute.gateway.networking.k8s.io/scout configured
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

The `scout` route has status conditions of its own now.

Check item 1. Read the conditions of both routes:

```sh
kubectl -n starfleet get httproute bridge \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl -n starfleet get httproute scout \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

Both routes report `Accepted=True` and `ResolvedRefs=True`. Check item 2. Read the count of the listener:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.status.listeners[0].attachedRoutes}{"\n"}'
```

```text
2
```

The listener holds 2 routes. At the start it held 1. Check item 3. Print the host names, the paths, and the backends of both routes:

```sh
kubectl -n starfleet get httproute \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.hostnames}{" "}{.spec.rules[0].matches[0].path}{" "}{.spec.rules[0].backendRefs[0].name}{":"}{.spec.rules[0].backendRefs[0].port}{"\n"}{end}'
```

```text
bridge ["starfleet.example.com"] {"type":"PathPrefix","value":"/productpage"} bridge:9080
scout ["starfleet.example.com"] {"type":"PathPrefix","value":"/reviews"} scout:9080
```

Both routes keep the host `starfleet.example.com` and the port `9080`. `bridge` sends `/productpage` to the Service `bridge`, and `scout` sends `/reviews` to the Service `scout`.

---

## Item 4: The `bridge` Page Returns `200`

> **Task item 4:** 10 out of 10 requests sent from the `shuttle` pod to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
done | sort | uniq -c
```

```text
  10 200
```

---

## Item 5: The `scout` Path Returns `200`

> **Task item 5:** 10 out of 10 requests sent the same way to `/reviews/0` return **`200`**.

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/reviews/0
done | sort | uniq -c
```

```text
  10 200
```

Any of the three `scout` versions may answer, because the route sends to the whole `scout` Service.

---

## Item 6: The `Gateway` And The App Are Unchanged

> **Task item 6:** The `Gateway` is **left unchanged**, and it stays the only `Gateway` in `starfleet`. Do not add, rename or remove Services or Deployments: fix the routes, not the app.

List the `Gateway` objects, and run the `Gateway`, Deployment and Service commands from the Start section again:

```sh
kubectl -n starfleet get gateway -o name
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
gateway.gateway.networking.k8s.io/starfleet-gateway
generation=1 uid=fc2a8392-03f4-4b6f-96b7-cb8fb0d53cd0
{"gatewayClassName":"istio","listeners":[{"allowedRoutes":{"namespaces":{"from":"Same"}},"hostname":"starfleet.example.com","name":"http","port":80,"protocol":"HTTP"}]}
NAME                      UID
bridge-v1                 6459ba28-7fca-4b9a-8ab5-f4c98624ab93
cargo-v1                  e0c0cd8e-64e6-438b-b05e-a51a8e80af13
navcom-v1                 55915f26-5b50-43eb-9185-ed1b971381f7
scout-v1                  467c6e82-b1e5-4685-a57a-654226cbc959
scout-v2                  1c3cf555-1581-4536-8638-a20048a00247
scout-v3                  fed17dca-008f-45cc-98a6-4844c4aa00db
shuttle                   e331545b-2ba0-48df-85d3-be77d57e79b5
starfleet-gateway-istio   45cd9f30-5faf-4589-a1d0-84169a3d4c2f
NAME                      PORT
bridge                    9080
cargo                     9080
navcom                    9080
scout                     9080
starfleet-gateway-istio   15021
```

The output is the same as before. There is one `Gateway`, with `generation=1` and the same spec. The Deployments have the same `UID` values, and the Services are the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-03/labs/lab-03
```

The grader reads the status of both routes and sends real requests through the gateway from the `shuttle` pod.

---

## Mistakes That Fail The Grader

- **Adding a Service named `brigde` (item 1).** It hides the typo instead of fixing it. The task expects the Services of the app only.
- **Creating a second `Gateway` named `starfleet-gate` (items 1 and 6).** That gives the `scout` route a gateway of its own. Both routes belong on `starfleet-gateway`, and there must be one `Gateway` only.
- **Changing the `Gateway` (item 6).** It was correct. A different host name, listener or `allowedRoutes` fails the task.
- **Changing the host name, the path or the port of a route while you fix it (item 3).** Only the typo was wrong.
- **Deleting a route instead of repairing it (items 1 and 2).** Both routes must exist and attach to the `Gateway`.
- **Stopping at `Accepted` (item 1).** The `bridge` route was `Accepted=True` from the start. Read every condition, not just the first.
