# Solution Walkthrough

The `Gateway` was correct from the start. Each `HTTPRoute` had one typo: one named a Service that does not exist, and the other named a `Gateway` that does not exist. The status conditions of the routes point at both.

## Step 1: Confirm the failures

Send one request to each path through the gateway, then read the last two lines of the gateway proxy's access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/reviews/0
kubectl logs -n starfleet deploy/starfleet-gateway-istio --tail=2
```

The output, with the log lines shortened:

```text
500
404
[2026-10-08T22:51:54.366Z] "GET /productpage HTTP/1.1" 500 NC cluster_not_found - "-" 0 0 2 - "10.244.0.12" "curl/8.11.1" ... starfleet.bridge.0
[2026-10-08T22:51:54.444Z] "GET /reviews/0 HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.12" "curl/8.11.1" ... - -
```

There are two different failures. `/productpage` gets `500` with the response flag `NC`, "no cluster": a rule matched (the log names the route `starfleet.bridge.0`), but it points at a destination the gateway proxy does not know. `/reviews/0` gets `404` with the flag `NR`, "no route": no rule on this gateway matches the request at all.

## Step 2: Ask the Gateway how many routes it holds

The `Gateway` status counts the routes attached to each listener. Compare that count with the routes that exist:

```sh
kubectl get gateway -n starfleet
kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{.status.listeners[0].attachedRoutes}{"\n"}'
kubectl get httproute -n starfleet
```

```text
NAME                CLASS   ADDRESS                                               PROGRAMMED   AGE
starfleet-gateway   istio   starfleet-gateway-istio.starfleet.svc.cluster.local   True         76s
1
NAME     HOSTNAMES                   AGE
bridge   ["starfleet.example.com"]   74s
scout    ["starfleet.example.com"]   74s
```

The `Gateway` is `PROGRAMMED`, and two routes exist, but its listener holds only `1`. One route never attached.

## Step 3: Read the status conditions of both routes

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl get httproute scout -n starfleet -o jsonpath='{.status.parents}{"\n"}'
```

```text
Accepted=True Accepted: Route was valid
ResolvedRefs=False BackendNotFound: backend(brigde.starfleet.svc.cluster.local) not found
[]
```

- `bridge` is attached (`Accepted=True`), but its backend is missing (`ResolvedRefs=False BackendNotFound`). The message names it: `brigde`, a typo.
- `scout` has no status at all. No controller wrote a status for it, so the fault is in its `parentRefs`.

`istioctl analyze -n starfleet` finds the first fault too. It reports `IST0171` for the `bridge` route and says nothing about `scout`, because a route with no status has no `False` condition to report (other warnings are left out):

```text
Warning [IST0171] (HTTPRoute starfleet/bridge) A condition with a negative status is present: type=ResolvedRefs, reason=BackendNotFound, message=backend(brigde.starfleet.svc.cluster.local) not found.
```

## Step 4: Compare the names with what exists

List the Services, and print the two names that the conditions point at:

```sh
kubectl get svc -n starfleet
kubectl get httproute bridge -n starfleet -o jsonpath='{.spec.rules[0].backendRefs[0].name}{"\n"}'
kubectl get httproute scout -n starfleet -o jsonpath='{.spec.parentRefs[0].name}{"\n"}'
```

```text
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)            AGE
bridge                    ClusterIP   10.96.233.229   <none>        9080/TCP           2m
cargo                     ClusterIP   10.96.149.103   <none>        9080/TCP           2m
navcom                    ClusterIP   10.96.235.248   <none>        9080/TCP           2m
scout                     ClusterIP   10.96.71.156    <none>        9080/TCP           2m
starfleet-gateway-istio   ClusterIP   10.96.100.96    <none>        15021/TCP,80/TCP   76s
brigde
starfleet-gate
```

The Service is `bridge`, not `brigde`. The `Gateway` is `starfleet-gateway`, not `starfleet-gate`.

## Step 5: Fix the bridge route

The fix changes only the backend name. Save this as `httproute-bridge.yaml`:

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

Apply it:

```sh
kubectl apply -f httproute-bridge.yaml
```

Then check the result:

```sh
kubectl get httproute bridge -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/productpage
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
200
```

## Step 6: Fix the scout route

The fix changes only the `parentRefs` name. Save this as `httproute-scout.yaml`:

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

Apply it:

```sh
kubectl apply -f httproute-scout.yaml
```

Then check the result:

```sh
kubectl get httproute scout -n starfleet \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{.status.listeners[0].attachedRoutes}{"\n"}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Host: starfleet.example.com" http://starfleet-gateway-istio.starfleet/reviews/0
```

```text
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
2
200
```

The `scout` route now has status conditions of its own, the `Gateway` holds both routes, and `scout` answers through the gateway. Its response body names the pod that answered, for example `"podname": "scout-v2-866c98b568-tw4rf"`. Any of the three `scout` versions may answer, because the route sends to the whole `scout` Service.

## Mistakes that fail the grader

- **Adding a Service named `brigde`.** It hides the typo instead of fixing it. The grader expects exactly the four Services of the app.
- **Creating a second `Gateway` named `starfleet-gate`.** That gives the `scout` route a gateway of its own. The task asks for both routes on `starfleet-gateway`, and for one `Gateway` only.
- **Changing the `Gateway`.** It was correct. A different host name, listener or `allowedRoutes` fails the grader.
- **Changing a route's host name, path or port while fixing it.** Only the typo was wrong.
- **Deleting a route instead of repairing it.** Both routes must exist and attach to the `Gateway`.
- **Stopping at "Accepted".** The `bridge` route was `Accepted=True` from the start. Read every condition, not just the first.
