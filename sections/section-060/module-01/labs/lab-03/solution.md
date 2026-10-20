# Solution Walkthrough

The gateway has a listener, but three mistakes stand between it and `bridge`. The `VirtualService` is not bound to the `Gateway`, the `Gateway` has a typo in its host, and the route goes to a host that does not exist. Each mistake hides the next one. You fix them one at a time, and each status code from the gateway points at the next fault. The three fixes belong to items 2, 1 and 3, in this order, and the status code changes after each one. Items 4 to 7 prove the result. A `Gateway` is the Istio object that opens listeners on a gateway proxy, and a `VirtualService` holds the routing rules for a host.

---

## Start: Confirm The Failure

Start the port forward. `kind` has no load balancer, so this is how you reach the gateway Service. Then send one request through the gateway, and read the access log of the gateway proxy. The proxy is the Envoy container that accepts the traffic from outside:

```sh
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
sleep 5
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
sleep 2
kubectl -n istio-ingress logs deploy/istio-ingress --tail=1
```

```text
404
[2026-10-20T21:44:38.744Z] "GET /productpage HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.6" "curl/8.7.1" "0e75411a-99e6-4f6c-a6c0-804a65bff58a" "starfleet.example.com" "-" - - 127.0.0.1:80 127.0.0.1:39036 - -
```

The gateway answers `404` with the response flag `NR` ("no route"). The gateway has a listener, so the selector of the `Gateway` works. But no route matched. If you get `000` right after you start the port forward, wait a few seconds and send the request again. List the two Istio objects, read the route table of the gateway proxy, and let Istio check the namespace:

```sh
kubectl -n starfleet get gateway,virtualservice
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress
istioctl analyze -n starfleet
```

```text
NAME                                            AGE
gateway.networking.istio.io/starfleet-gateway   8s

NAME                                        GATEWAYS   HOSTS                       AGE
virtualservice.networking.istio.io/bridge              ["starfleet.example.com"]   8s
NAME        VHOST NAME       DOMAINS     MATCH                  VIRTUAL SERVICE
http.80     blackhole:80     *           /*                     404
            backend          *           /stats/prometheus*     
            backend          *           /healthz/ready*        
Error [IST0101] (VirtualService starfleet/bridge) Referenced host not found: "bridges"
Error: Analyzers found issues when analyzing namespace: starfleet.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
```

The `GATEWAYS` column of the `VirtualService` is empty. It has no `gateways:` field, so its routes go to `mesh` (all sidecar proxies) and never reach the gateway. The route table confirms it: it holds only `blackhole:80`, which answers `404` to every request. `istioctl analyze` finds a second fault: the `VirtualService` sends requests to `bridges`, but the Service is called `bridge`. The analyzer does not report the missing `gateways:` field, because a `VirtualService` for `mesh` is a valid object.

Save the state that item 7 must keep:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n istio-ingress get deploy istio-ingress -o jsonpath='{.metadata.uid} {.spec.template.metadata.labels.istio}{"\n"}'
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
NAME        UID
bridge-v1   7c4aa676-826d-4bdd-9cac-d20ad5a2d744
cargo-v1    79ee55dd-d97c-4fd7-8886-813efd727ff1
navcom-v1   cb9a7ec4-e5f8-465d-9c09-55353cf8c10f
scout-v1    09fc0083-44eb-4446-9368-2934e394e715
scout-v2    c13a0f58-38cb-4d1f-8896-fc48b8e7b14a
scout-v3    b58c6265-6b6a-4476-a017-f0b734aa5e70
shuttle     44741b6e-e951-48c2-a1d4-4eb0e6940e85
1c27e814-56b9-4db7-b1c0-4f2660eb7021 ingress
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

---

## Item 2: Bind The `VirtualService` To The `Gateway`

> **Task item 2:** The `VirtualService` named `bridge` in `starfleet` serves the host `starfleet.example.com` and is **bound to `starfleet-gateway`** with its `gateways` field.

Start with the binding, because it is the first fault. Add `gateways:` and leave the destination as it is for now. Save this as `virtualservice-bridge.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridges
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Send the request again, and let Istio check the namespace:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
istioctl analyze -n starfleet 2>&1 | grep -E "IST"
```

```text
404
Error [IST0101] (VirtualService starfleet/bridge) Referenced host not found: "bridges"
Warning [IST0132] (VirtualService starfleet/bridge) one or more host [starfleet.example.com] defined in VirtualService starfleet/bridge not found in Gateway starfleet/starfleet-gateway.
```

The answer is still `404`, but now the analyzer shows the next fault. The message `IST0132` says that the `Gateway` does not serve the host `starfleet.example.com`.

---

## Item 1: Fix The Host Of The `Gateway`

> **Task item 1:** The `Gateway` named `starfleet-gateway` in `starfleet` selects the gateway pods (`istio: ingress`) and has **exactly one** server: port `80`, protocol `HTTP`, host `starfleet.example.com` only. Do **not** use `*`.

Read the host of the `Gateway` letter by letter:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.servers[0].hosts}{"\n"}'
```

```text
["starfleet.exmaple.com"]
```

The host is `starfleet.exmaple.com`. The letters `m` and `a` are swapped. Do not use `*` to get around the typo. The `Gateway` must serve only `starfleet.example.com`. Write the `Gateway` again with the correct host, and keep the selector, the port and the protocol as they are. Save this as `gateway-starfleet.yaml`:

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

Send the request again, and read the access log of the gateway:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
sleep 2
kubectl -n istio-ingress logs deploy/istio-ingress --tail=1
```

```text
503
[2026-10-20T21:44:58.370Z] "GET /productpage HTTP/1.1" 503 NC cluster_not_found - "-" 0 0 0 - "10.244.0.6" "curl/8.7.1" "c711fe0b-174c-4d48-b3a9-cd43d8af8130" "starfleet.example.com" "-" - - 127.0.0.1:80 127.0.0.1:39960 - -
```

The answer moved from `404` to `503`. Routing works now: a route matched. But the destination does not exist, so the access log shows `NC cluster_not_found` ("no cluster"). That is the typo `bridges`.

---

## Item 3: Point The Routes At The `bridge` Service

> **Task item 3:** Every route in it goes to the `bridge` Service on port `9080`. Do not create a new Service to match a wrong name.

In `virtualservice-bridge.yaml`, change `host: bridges` to `host: bridge`. Do not create a Service called `bridges`. The route part of the file now looks like this:

```yaml
    route:
    - destination:
        host: bridge
        port:
          number: 9080
```

Apply the file again:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Check item 3. Print the destination of each route, and list the Services:

```sh
kubectl -n starfleet get virtualservice bridge -o jsonpath='{range .spec.http[*]}{.route[*].destination}{"\n"}{end}'
kubectl -n starfleet get svc -o name
```

```text
{"host":"bridge","port":{"number":9080}}
service/bridge
service/cargo
service/navcom
service/scout
```

The only route goes to `bridge` on port `9080`, and no new Service exists. Check items 1 and 2 once more with the final objects:

```sh
kubectl -n starfleet get gateway starfleet-gateway -o jsonpath='{.spec.selector} {.spec.servers}{"\n"}'
kubectl -n starfleet get virtualservice bridge -o jsonpath='{.spec.hosts} gateways={.spec.gateways}{"\n"}'
```

```text
{"istio":"ingress"} [{"hosts":["starfleet.example.com"],"port":{"name":"http","number":80,"protocol":"HTTP"}}]
["starfleet.example.com"] gateways=["starfleet-gateway"]
```

The `Gateway` selects `istio=ingress` and has one server, with port 80, protocol `HTTP` and one host. The `VirtualService` serves `starfleet.example.com` and is bound to `starfleet-gateway`.

---

## Item 4: The Gateway Proxy Holds The Routes And A Healthy Endpoint

> **Task item 4:** The gateway's proxy holds a `/productpage` route for `starfleet.example.com` from the `bridge` `VirtualService`, and a healthy endpoint for `bridge`.

`istiod`, the Istio control plane, sends the configuration to the gateway proxy. Read the route table and the endpoints of the `bridge` cluster. A cluster is a named destination in Envoy, and an endpoint is the address of one pod:

```sh
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress | grep -E "NAME|starfleet"
istioctl proxy-config endpoints deploy/istio-ingress -n istio-ingress \
  --cluster "outbound|9080||bridge.starfleet.svc.cluster.local"
```

```text
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     /productpage           bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /static*               bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /login                 bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /logout                bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /api/v1/products*      bridge.starfleet
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.12:9080     HEALTHY     OK                outbound|9080||bridge.starfleet.svc.cluster.local
```

The gateway holds the routes for `starfleet.example.com`, from `bridge.starfleet`, and the `bridge` cluster has a healthy endpoint. The pod address changes with every run.

---

## Item 5: Both Paths Return `200`

> **Task item 5:** All 10 out of 10 requests to `/productpage` with `Host: starfleet.example.com`, sent through the gateway Service, get `200`. `/api/v1/products` gets `200` too.

```sh
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
done | sort | uniq -c
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/api/v1/products
```

```text
  10 200
200
```

All 10 requests to `/productpage` and the request to `/api/v1/products` return `200`.

---

## Item 6: Other Hosts And Other Paths Are Not Served

> **Task item 6:** A request with `Host: other.example.com` does **not** get `200`, and `/admin` with `Host: starfleet.example.com` gets `404` (no catch-all route).

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: other.example.com" http://localhost:8080/productpage
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/admin
istioctl analyze -n starfleet
```

```text
404
404

✔ No validation issues found when analyzing namespace: starfleet.
```

The other host gets `404`, because the listener has no routes for it. The path `/admin` gets `404`, because the `VirtualService` has no catch-all route. The analyzer finds no problem.

---

## Item 7: Nothing Else Changed

> **Task item 7:** Leave the gateway Deployment, its pod labels, the `starfleet` Deployments and the Services unchanged. Do not add or remove workloads.

Run the three commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n istio-ingress get deploy istio-ingress -o jsonpath='{.metadata.uid} {.spec.template.metadata.labels.istio}{"\n"}'
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
```

```text
NAME        UID
bridge-v1   7c4aa676-826d-4bdd-9cac-d20ad5a2d744
cargo-v1    79ee55dd-d97c-4fd7-8886-813efd727ff1
navcom-v1   cb9a7ec4-e5f8-465d-9c09-55353cf8c10f
scout-v1    09fc0083-44eb-4446-9368-2934e394e715
scout-v2    c13a0f58-38cb-4d1f-8896-fc48b8e7b14a
scout-v3    b58c6265-6b6a-4476-a017-f0b734aa5e70
shuttle     44741b6e-e951-48c2-a1d4-4eb0e6940e85
1c27e814-56b9-4db7-b1c0-4f2660eb7021 ingress
NAME     PORT
bridge   9080
cargo    9080
navcom   9080
scout    9080
```

The output is the same as before. The same Deployments exist with the same `UID` values, the gateway pods keep the label `istio=ingress`, and the Services are the same. Stop the port forward with `kill %1` when you are done.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-03
```

The grader sends live requests from the `shuttle` pod to the gateway Service, and reads the configuration of the gateway proxy.

---

## Mistakes That Fail The Grader

- **Setting `hosts: ["*"]` on the `Gateway` to get around the typo (item 1).** The `Gateway` must serve only `starfleet.example.com`.
- **Creating a Service called `bridges` to match the typo (item 3).** The grader checks that no such Service exists and that every route goes to `bridge` on port `9080`.
- **Adding a catch-all route (item 6).** The path `/admin` must still get `404`.
- **Leaving out `/api/v1/products` (item 5).** It must get `200` too.
- **Renaming the objects or changing the labels of the gateway pods (items 1, 2 and 7).** The grader looks for `starfleet-gateway` and `bridge` in `starfleet`, and for gateway pods with the label `istio=ingress`.
