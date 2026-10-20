# Solution Walkthrough

The `VirtualService` was correct all along. The `Gateway` selected gateway pods by a label that no pod carries. So `istiod`, the Istio control plane, sent the listener to no gateway pod, and nothing listened on port `80`. A `Gateway` is the Istio object that opens listeners on a gateway proxy, and a `VirtualService` holds the routing rules for a host. The Start section finds the cause. Items 1 and 2 are the fix, and items 3 to 7 prove the result.

---

## Start: Confirm The Failure And Find The Cause

The task says that requests from outside get no response at all. Start the port forward, and send one request through the gateway. `kind` has no load balancer, so the port forward is how you reach the gateway Service:

```sh
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
```

```text
000
```

`000` means that `curl` got no response at all. That points at the `Gateway`, not at the `VirtualService`, because nothing listens on port `80`. A missing route would give `404` instead. Stop the port forward with `kill %1` for now. Compare the label of the gateway pod with the selector of the `Gateway`, and let Istio check the namespace. Then list the listeners of the gateway proxy. The proxy is the Envoy container that accepts the traffic, and a listener is the part of Envoy that accepts connections on one address and port:

```sh
kubectl -n istio-ingress get pods -L istio
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.selector}{"\n"}'
istioctl analyze -n starfleet
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress
```

```text
NAME                             READY   STATUS    RESTARTS   AGE   ISTIO
istio-ingress-5f768fb4b6-9c2cw   1/1     Running   0          67s   ingress
{"istio":"ingressgateway"}
Error [IST0101] (Gateway starfleet/starfleet-gateway) Referenced selector not found: "istio=ingressgateway"
Error: Analyzers found issues when analyzing namespace: starfleet.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

The pod carries `istio=ingress`. The `Gateway` asks for `istio=ingressgateway`, which is the label of an `istioctl` install. This Helm install does not use it. The message `IST0101` names the selector that matches no pod. The listener list has only the health port `15021` and the metrics port `15090`, and no port `80`.

Save the state that items 6 and 7 must keep:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.servers}{"\n"}'
kubectl -n starfleet get virtualservice bridge -o jsonpath='generation={.metadata.generation} {.spec.hosts} {.spec.gateways}{"\n"}'
kubectl -n starfleet get virtualservice bridge -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n istio-ingress get deploy istio-ingress -o jsonpath='{.metadata.uid} {.spec.template.metadata.labels.istio}{"\n"}'
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
[{"hosts":["starfleet.example.com"],"port":{"name":"http","number":80,"protocol":"HTTP"}}]
generation=1 ["starfleet.example.com"] ["starfleet-gateway"]
[{"match":[{"uri":{"exact":"/productpage"}},{"uri":{"prefix":"/static"}},{"uri":{"exact":"/login"}},{"uri":{"exact":"/logout"}},{"uri":{"prefix":"/api/v1/products"}}],"route":[{"destination":{"host":"bridge","port":{"number":9080}}}]}]
NAME        UID
bridge-v1   91080beb-3b7b-4c57-ae77-11c7b7a14b07
cargo-v1    e08a52bf-1c3b-4891-9b48-6c6612b54cbb
navcom-v1   2d3e0aa4-6fa6-4449-8c26-45d30b39c1b4
scout-v1    cc5d214a-01f2-4814-8935-2d59319c6d28
scout-v2    b90e6ea2-85e4-4df1-8ac8-8776c9af6061
scout-v3    13614afd-984f-4e4a-8fb2-ddad5d2c9847
shuttle     1dce7db5-83c9-463d-b7a1-d39fa555b010
9d3f71de-1a59-413b-b8ff-301f524b2a3c ingress
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

---

## Items 1 And 2: Fix The Selector, Keep The Server

> **Task item 1:** The `Gateway` named `starfleet-gateway` in `starfleet` selects the ingress gateway pods in `istio-ingress`.
>
> **Task item 2:** It keeps **exactly one** server: port `80`, protocol `HTTP`, host `starfleet.example.com` only. Do **not** use `*`.

Change only the selector, and keep the rest of the `Gateway`. Fix the `Gateway`, not the gateway pods. Save this as `gateway-starfleet.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
```

Apply it:

```sh
kubectl apply -f gateway-starfleet.yaml
```

```text
gateway.networking.istio.io/starfleet-gateway configured
```

Check item 1. Print the selector, and list the pod label that it must match:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n istio-ingress get pods -L istio | awk '{print $1,$NF}'
```

```text
{"istio":"ingress"}
NAME ISTIO
istio-ingress-5f768fb4b6-9c2cw ingress
```

The selector `istio=ingress` now matches the gateway pod. Check item 2. Print the servers:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.servers}{"\n"}'
```

```text
[{"hosts":["starfleet.example.com"],"port":{"name":"http","number":80,"protocol":"HTTP"}}]
```

There is one server, on port 80, with the protocol `HTTP` and the single host `starfleet.example.com`.

---

## Item 3: The Gateway Proxy Has The Listener And The Routes

> **Task item 3:** The gateway's proxy has a listener on port `80`, and its route table holds the `bridge` routes for `starfleet.example.com`.

Wait a few seconds for `istiod` to send the change. Then read the listener and the route table of the gateway proxy, and let Istio check the namespace:

```sh
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress --port 80
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress | grep -E "NAME|starfleet"
istioctl analyze -n starfleet
```

```text
ADDRESSES PORT MATCH DESTINATION
0.0.0.0   80   ALL   Route: http.80
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     /productpage           bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /static*               bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /login                 bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /logout                bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /api/v1/products*      bridge.starfleet

✔ No validation issues found when analyzing namespace: starfleet.
```

The listener on port `80` exists, and its route table `http.80` holds the routes of the `bridge` `VirtualService`. That object was already bound to `starfleet-gateway`. It only needed a `Gateway` that selects a real gateway pod.

---

## Items 4 And 5: Live Requests

> **Task item 4:** All 10 out of 10 requests to `/productpage` with `Host: starfleet.example.com`, sent through the gateway Service, get `200`.
>
> **Task item 5:** A request with `Host: other.example.com` does **not** get `200`.

Start the port forward again, and send 10 requests for `bridge`, and one for a host that the `Gateway` does not serve:

```sh
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
sleep 4
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
done | sort | uniq -c
curl -s -o /dev/null -w "other host: %{http_code}\n" -H "Host: other.example.com" http://localhost:8080/productpage
```

```text
  10 200
other host: 404
```

All 10 requests for `bridge` return `200`. The other host returns `404`, because the listener has no routes for it. Stop the port forward with `kill %1`.

---

## Item 6: The `VirtualService` Is Unchanged

> **Task item 6:** The `VirtualService` named `bridge` is **left unchanged**.

Run the two `VirtualService` commands from the Start section again:

```sh
kubectl -n starfleet get virtualservice bridge -o jsonpath='generation={.metadata.generation} {.spec.hosts} {.spec.gateways}{"\n"}'
kubectl -n starfleet get virtualservice bridge -o jsonpath='{.spec.http}{"\n"}'
```

```text
generation=1 ["starfleet.example.com"] ["starfleet-gateway"]
[{"match":[{"uri":{"exact":"/productpage"}},{"uri":{"prefix":"/static"}},{"uri":{"exact":"/login"}},{"uri":{"exact":"/logout"}},{"uri":{"prefix":"/api/v1/products"}}],"route":[{"destination":{"host":"bridge","port":{"number":9080}}}]}]
```

The `generation` is still `1`, so nobody edited the object, and the routes are the same.

---

## Item 7: Nothing Else Changed

> **Task item 7:** Leave the gateway Deployment, its pod labels, the `starfleet` Deployments and the Services unchanged.

Run the Deployment, label and Service commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n istio-ingress get deploy istio-ingress -o jsonpath='{.metadata.uid} {.spec.template.metadata.labels.istio}{"\n"}'
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
NAME        UID
bridge-v1   91080beb-3b7b-4c57-ae77-11c7b7a14b07
cargo-v1    e08a52bf-1c3b-4891-9b48-6c6612b54cbb
navcom-v1   2d3e0aa4-6fa6-4449-8c26-45d30b39c1b4
scout-v1    cc5d214a-01f2-4814-8935-2d59319c6d28
scout-v2    b90e6ea2-85e4-4df1-8ac8-8776c9af6061
scout-v3    13614afd-984f-4e4a-8fb2-ddad5d2c9847
shuttle     1dce7db5-83c9-463d-b7a1-d39fa555b010
9d3f71de-1a59-413b-b8ff-301f524b2a3c ingress
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

The output is the same as before. The same Deployments exist with the same `UID` values, and the gateway pods still carry the label `istio=ingress`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-02
```

The grader sends live requests from the `shuttle` pod to the gateway Service, and reads the configuration of the gateway proxy.

---

## Mistakes That Fail The Grader

- **Changing the labels of the gateway pods to match the `Gateway` (items 1 and 7).** The grader checks that the Deployment still labels its pods `istio=ingress`. Fix the `Gateway`, not the gateway.
- **Setting `hosts: ["*"]` (item 2).** The `Gateway` must serve only `starfleet.example.com`.
- **Editing the `VirtualService` (item 6).** It was correct. The grader checks that it still serves `starfleet.example.com`, links to `starfleet-gateway` and routes to `bridge` on port `9080`.
- **Renaming the `Gateway` or moving it to another namespace (item 1).** The `VirtualService` refers to `starfleet-gateway` by its bare name, so Istio looks for it in `starfleet`.
