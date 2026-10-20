# Solution Walkthrough

The `Ingress` was correct all along. The `IngressClass` that it names had a controller string that no controller answers. So `istiod`, the Istio control plane, never took the `Ingress`, and the ingress gateway never got any configuration for it. An `Ingress` is the Kubernetes object that exposes a Service to outside traffic, and an `IngressClass` tells Kubernetes which controller serves it. The Start section finds the cause. Item 1 is the fix, and items 2 to 6 prove the result.

---

## Start: Confirm The Failure And Find The Cause

The task says that no request for `starfleet.example.com` gets through the ingress gateway. The ingress gateway is the Envoy proxy that accepts traffic from outside the cluster. Send one request through the gateway from the `shuttle` pod, then look at the `Ingress`, and read the last line of the access log of the sidecar proxy of `shuttle`. Wait a moment before you read the log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Host: starfleet.example.com" http://istio-ingressgateway.istio-system/anything/dock/1
kubectl -n starfleet get ingress
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
503
NAME        CLASS   HOSTS                   ADDRESS   PORTS   AGE
starfleet   istio   starfleet.example.com             80      1s
[2026-10-20T21:49:49.371Z] "GET /anything/dock/1 HTTP/1.1" 503 UF upstream_reset_before_response_started{remote_connection_failure|delayed_connect_error:_Connection_refused} - "delayed_connect_error:_Connection_refused" 0 98 0 - "-" "curl/8.11.1" "5a6557d2-3e46-4891-afc9-73a2788d3b02" "starfleet.example.com" "10.96.112.202:80" PassthroughCluster - 10.96.112.202:80 10.244.0.9:59704 - allow_any
```

The `CLASS` column says `istio`, so the `Ingress` looks correct. The response flag `UF` ("upstream connection failure") with `Connection_refused` shows that the gateway does not even listen on port `80`. From outside the cluster, through a port forward, the same failure would show as `000`. Now list the listeners and the routes of the gateway, and the ingress classes:

```sh
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system
kubectl get ingressclass
```

```text
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
NAME     VHOST NAME     DOMAINS     MATCH                  VIRTUAL SERVICE
         backend        *           /stats/prometheus*     
         backend        *           /healthz/ready*        
NAME    CONTROLLER                     PARAMETERS   AGE
istio   istio.io/ingress-controllers   <none>       4s
```

The gateway has only its health and metrics ports. `istiod` built nothing from the `Ingress`, which means it does not treat the `Ingress` as its own. The controller of the class is `istio.io/ingress-controllers`, with an `s` at the end. `istiod` serves only classes whose controller is exactly `istio.io/ingress-controller`. The class exists and the `Ingress` points at it, but no controller serves it. That is the fault.

Save the state that items 2 and 6 must keep:

```sh
kubectl -n starfleet get ingress starfleet -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
kubectl -n istio-system get deploy istio-ingressgateway -o jsonpath='{.metadata.uid} {.metadata.generation}{"\n"}'
```

```text
generation=1 uid=d007d811-edfe-4536-a372-2f6b674e96a3
{"ingressClassName":"istio","rules":[{"host":"starfleet.example.com","http":{"paths":[{"backend":{"service":{"name":"probe","port":{"number":8000}}},"path":"/anything","pathType":"Prefix"}]}}]}
NAME       UID
probe-v1   9130ddab-b21d-4967-a070-fbd42c552612
probe-v2   45524927-71b3-46f1-9537-703afb9d06c0
shuttle    64c3a627-8ccf-47ea-a877-621577edec89
NAME    PORT
probe   8000
2c257732-905e-40a6-92f3-b466d3afeb05 1
```

---

## Item 1: Recreate The `IngressClass` With The Right Controller

> **Task item 1:** The `IngressClass` named `istio` exists and names Istio's ingress controller, `istio.io/ingress-controller`.

The obvious fix is to edit the field in place. Kubernetes refuses:

```sh
kubectl patch ingressclass istio --type merge -p '{"spec":{"controller":"istio.io/ingress-controller"}}'
```

```text
The IngressClass "istio" is invalid: spec.controller: Invalid value: "istio.io/ingress-controller": field is immutable
```

The field `spec.controller` is immutable, which means that Kubernetes does not allow any change to it. Delete the class, and create it again. Save this as `ingressclass-istio.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Delete the old class and apply the file:

```sh
kubectl delete ingressclass istio
kubectl apply -f ingressclass-istio.yaml
```

```text
ingressclass.networking.k8s.io "istio" deleted
ingressclass.networking.k8s.io/istio created
```

The `Ingress` needs no change. It still names the class `istio`, and that name now points at the right controller. Check item 1:

```sh
kubectl get ingressclass
kubectl get ingressclass istio -o jsonpath='{.spec.controller}{"\n"}'
```

```text
NAME    CONTROLLER                    PARAMETERS   AGE
istio   istio.io/ingress-controller   <none>       8s
istio.io/ingress-controller
```

The class `istio` exists with the controller `istio.io/ingress-controller`. Do not trust the `CLASS` column of the `Ingress` as a proof. It only repeats the name in `ingressClassName`. The `CONTROLLER` column of the class is the proof.

---

## Item 2: The `Ingress` Is Unchanged

> **Task item 2:** The `Ingress` named `starfleet` is **left unchanged**: it still names the class `istio` and has its one rule.

Run the first command from the Start section again, and list the `Ingress` objects:

```sh
kubectl -n starfleet get ingress starfleet -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get ingress
```

```text
generation=1 uid=d007d811-edfe-4536-a372-2f6b674e96a3
{"ingressClassName":"istio","rules":[{"host":"starfleet.example.com","http":{"paths":[{"backend":{"service":{"name":"probe","port":{"number":8000}}},"path":"/anything","pathType":"Prefix"}]}}]}
NAME        CLASS   HOSTS                   ADDRESS   PORTS   AGE
starfleet   istio   starfleet.example.com             80      12s
```

The `generation` is still `1`, and the spec is the same: class `istio`, one rule for `starfleet.example.com` and the path `/anything`.

---

## Item 3: Five Requests Return `200`

> **Task item 3:** 5 out of 5 requests sent from the `shuttle` pod to `http://istio-ingressgateway.istio-system/anything/dock/<n>` with the header `Host: starfleet.example.com` get `200`.

`istiod` sends the configuration to the gateway. Wait a few seconds, then send five requests:

```sh
for i in 1 2 3 4 5; do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' \
    -H "Host: starfleet.example.com" http://istio-ingressgateway.istio-system/anything/dock/$i
done | sort | uniq -c
```

```text
   5 200
```

All five requests return `200`. If you still get `503`, wait a few seconds and send them again.

---

## Item 4: Other Paths Still Return `404`

> **Task item 4:** A request to `/status/200` on the same host still gets `404` from the gateway: only `/anything` is routed.

Send the request, then read the route table and the last access log line of the gateway:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Host: starfleet.example.com" http://istio-ingressgateway.istio-system/status/200
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system
sleep 2
kubectl -n istio-system logs deploy/istio-ingressgateway --tail=1
```

```text
404
NAME        VHOST NAME                   DOMAINS                   MATCH                    VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     PathPrefix:/anything     starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
            backend                      *                         /stats/prometheus*       
            backend                      *                         /healthz/ready*          
[2026-10-20T21:50:00.864Z] "GET /status/200 HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.9" "curl/8.11.1" "5e0134ee-5846-4eb7-90f0-9514d5e8f772" "starfleet.example.com" "-" - - 10.244.0.6:80 10.244.0.9:60198 - -
```

The request returns `404` with the flag `NR` ("no route"). The route table that `istiod` built from the `Ingress` has one route for the host, with the match `PathPrefix:/anything`. The column `VIRTUAL SERVICE` shows the name of the generated configuration, which ends in `istio-autogenerated-k8s-ingress`.

---

## Item 5: No `Gateway` And No `VirtualService`

> **Task item 5:** No `Gateway` and no `VirtualService` exist anywhere in the cluster. The gateway must serve the `Ingress` itself.

```sh
kubectl get gateway,virtualservice -A
```

```text
No resources found
```

There is no `Gateway` and no `VirtualService`. Requests would get through with them, but the task is to make the gateway serve the `Ingress` itself.

---

## Item 6: Nothing Else Changed

> **Task item 6:** The Deployments, the Services and the ingress gateway stay unchanged.

Run the three commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
kubectl -n istio-system get deploy istio-ingressgateway -o jsonpath='{.metadata.uid} {.metadata.generation}{"\n"}'
```

```text
NAME       UID
probe-v1   9130ddab-b21d-4967-a070-fbd42c552612
probe-v2   45524927-71b3-46f1-9537-703afb9d06c0
shuttle    64c3a627-8ccf-47ea-a877-621577edec89
NAME    PORT
probe   8000
2c257732-905e-40a6-92f3-b466d3afeb05 1
```

The output is the same as before. The Deployments have the same `UID` values, and the Service is the same. The ingress gateway has the same `UID` and still has `generation` `1`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-02
```

The grader sends live requests from the `shuttle` pod through the gateway.

---

## Mistakes That Fail The Grader

- **Trusting the `CLASS` column of the `Ingress` (item 1).** It only repeats the name in `ingressClassName`. It does not tell you whether any controller serves that class. Check the `CONTROLLER` column of `kubectl get ingressclass`.
- **Trying to patch `spec.controller` (item 1).** The field cannot be changed. Delete the `IngressClass` and create it again.
- **Deleting the class and stopping there (item 1).** The class `istio` must exist with the controller of Istio.
- **Changing the `Ingress` instead (item 2).** Pointing it at a new class, or editing its rule, fails the task. The `Ingress` was correct and must stay unchanged.
- **Working around it with a `Gateway` and a `VirtualService` (item 5).** Requests would get through, but any `Gateway` or `VirtualService` fails the task.
