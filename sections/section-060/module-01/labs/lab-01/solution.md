# Solution Walkthrough

You need three objects: one `Gateway`, which opens the listener, and two `VirtualService` objects, which hold the routes for each host. One line in each `VirtualService`, the `gateways:` field, decides whether any of it works. Items 1 and 2 are the `Gateway`. Items 3 and 4 are the `VirtualService` objects. Items 5 to 10 prove the result with real requests and with the route table of the gateway proxy.

---

## Start: See The Starting State

The task says that the ingress gateway has no configuration yet. The ingress gateway is the Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. Look at the gateway pod, the Istio objects of the namespace, the listeners of the gateway proxy, and the identity of the workloads:

```sh
kubectl -n istio-system get pods -l istio=ingressgateway | awk '{print $1,$2,$3}'
kubectl -n ingress-demo get gateway,virtualservice
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
kubectl -n ingress-demo get deploy,svc -o custom-columns=KIND:.kind,NAME:.metadata.name,UID:.metadata.uid
```

```text
NAME READY STATUS
istio-ingressgateway-7f54444996-zgmp7 1/1 Running
No resources found in ingress-demo namespace.
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
KIND         NAME                 UID
Deployment   booking-service-v1   eadf1de0-7233-4bb9-9a53-b68f7b5316ed
Deployment   catalog-service-v1   6bdb8f0f-b806-449f-8efb-40cc9a9c8ebc
Service      booking-service      7e59d437-3b73-4e31-a1b9-b0e8ba274779
Service      catalog-service      97b005f3-923e-41b2-b360-f5fbe2fd6b8a
```

The pod is `1/1`: an Envoy proxy with no application container. It is healthy, but it has only its health and metrics listeners. No `Gateway` configures it yet, so nothing listens on port `8080`, the container port behind the Service port `80`.

`kind` has no load balancer, so the gateway Service never gets an `EXTERNAL-IP`, and you reach it with `kubectl port-forward`. Do not start the port forward yet. With no listener on port `8080`, the first request gets an empty reply (`curl` prints `000`), and the port forward stops.

---

## Items 1 And 2: Open The Listener

> **Task item 1:** Create a `Gateway` named **`public-gateway`** in namespace **`ingress-demo`**, selecting the standard ingress gateway pods (`istio: ingressgateway`).
>
> **Task item 2:** It must open **one** server on **port 80**, protocol **`HTTP`**, accepting exactly these two hosts:
>
> * `booking.ica.local`
> * `catalog.ica.local`
>
> Do **not** use `*`. The listener must reject any other host.

A `Gateway` is the Istio object that opens listeners on the gateway proxy. The `selector` is a pod label selector. It matches the gateway pods that the `demo` profile installed. The `Gateway` lives in `ingress-demo`, while the pod that it configures lives in `istio-system`. The selector is the only link between them. `protocol: HTTP` lets the gateway route by host and path. Save this as `gateway-public-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: ingress-demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - booking.ica.local
        - catalog.ica.local
```

Apply it:

```sh
kubectl apply -f gateway-public-gateway.yaml
```

```text
gateway.networking.istio.io/public-gateway created
```

Check items 1 and 2. Print the selector and the servers, and look for the new listener on the gateway proxy. `istiod`, the Istio control plane, sends the configuration to the proxy, so wait a few seconds:

```sh
kubectl -n ingress-demo get gateway public-gateway -o jsonpath='{.spec.selector} {.spec.servers}{"\n"}'
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system | grep -E "ADDRESSES|8080"
```

```text
{"istio":"ingressgateway"} [{"hosts":["booking.ica.local","catalog.ica.local"],"port":{"name":"http","number":80,"protocol":"HTTP"}}]
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   8080  ALL   Route: http.8080
```

The `Gateway` selects the standard ingress pods. It has one server, on port 80, with the protocol `HTTP` and exactly two hosts, and no `*`. The gateway proxy now has a listener on port `8080`.

Start the port forward now, and send a first request:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
sleep 4
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
404
```

This is expected. The listener exists now, but it has no routes, so the gateway answers `404`.

---

## Item 3: The `VirtualService` For `booking.ica.local`

> **Task item 3:** Create a `VirtualService` named **`booking`** for host `booking.ica.local`, **bound to `public-gateway`**, routing URI prefix **`/book`** to `booking-service` on port 80.

A `VirtualService` holds the routing rules for a host. The `gateways:` field is the key line. Without it, the routes go to `mesh`, which means all sidecar proxies, and the gateway keeps answering `404`. `istioctl analyze` stays clean in that case, because a `VirtualService` that is not bound to a gateway is still a valid object. Save this as `virtualservice-booking.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: ingress-demo
spec:
  hosts:
    - booking.ica.local
  gateways:
    - public-gateway
  http:
    - match:
        - uri:
            prefix: /book
      route:
        - destination:
            host: booking-service
            port:
              number: 80
```

Apply it:

```sh
kubectl apply -f virtualservice-booking.yaml
```

```text
virtualservice.networking.istio.io/booking created
```

Check item 3:

```sh
kubectl -n ingress-demo get virtualservice booking -o jsonpath='{.spec.hosts} {.spec.gateways} {.spec.http}{"\n"}'
```

```text
["booking.ica.local"] ["public-gateway"] [{"match":[{"uri":{"prefix":"/book"}}],"route":[{"destination":{"host":"booking-service","port":{"number":80}}}]}]
```

The object is for the host `booking.ica.local`, bound to `public-gateway`, and it routes the prefix `/book` to `booking-service` on port 80.

---

## Item 4: The `VirtualService` For `catalog.ica.local`

> **Task item 4:** Create a `VirtualService` named **`catalog`** for host `catalog.ica.local`, **bound to `public-gateway`**, routing URI prefix **`/items`** to `catalog-service` on port 80.

Each host gets its own `VirtualService`, bound to the same `Gateway`. Both use the same listener, and the host of each object keeps their routes apart. Save this as `virtualservice-catalog.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: catalog
  namespace: ingress-demo
spec:
  hosts:
    - catalog.ica.local
  gateways:
    - public-gateway
  http:
    - match:
        - uri:
            prefix: /items
      route:
        - destination:
            host: catalog-service
            port:
              number: 80
```

Apply it:

```sh
kubectl apply -f virtualservice-catalog.yaml
```

```text
virtualservice.networking.istio.io/catalog created
```

Check item 4. Print the object, and let Istio check the namespace:

```sh
kubectl -n ingress-demo get virtualservice catalog -o jsonpath='{.spec.hosts} {.spec.gateways} {.spec.http}{"\n"}'
istioctl analyze -n ingress-demo
```

```text
["catalog.ica.local"] ["public-gateway"] [{"match":[{"uri":{"prefix":"/items"}}],"route":[{"destination":{"host":"catalog-service","port":{"number":80}}}]}]

✔ No validation issues found when analyzing namespace: ingress-demo.
```

---

## Items 5 To 8: The Four Requests

> **Task item 5:** `GET /book` with `Host: booking.ica.local` returns **200**.
>
> **Task item 6:** `GET /items` with `Host: catalog.ica.local` returns **200**.
>
> **Task item 7:** `GET /book` with `Host: unknown.ica.local` does **not** return 200. The listener only accepts the two named hosts.
>
> **Task item 8:** `GET /book` with `Host: catalog.ica.local` does **not** return 200. Each host only carries its own routes.

Send the four requests with the right `Host` header. Without the header, `curl` sends `localhost:8080` as the host, which matches no host on the listener:

```sh
for request in "booking.ica.local /book" "catalog.ica.local /items" \
               "unknown.ica.local /book" "catalog.ica.local /book"; do
  read -r host uri <<< "$request"
  printf '%-20s %-8s -> ' "$host" "$uri"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $host" "http://$GATEWAY_URL$uri"
done
```

```text
booking.ica.local    /book    -> 200
catalog.ica.local    /items   -> 200
unknown.ica.local    /book    -> 404
catalog.ica.local    /book    -> 404
```

Items 5 and 6 return `200`. The last two requests fail for different reasons. The host `unknown.ica.local` matched no host on the listener, so the gateway had no routes for it (item 7). The host `catalog.ica.local` matched a host on the listener, but there is no route for the path `/book` under that host, because the `catalog` object matches only `/items` (item 8). Both answers are `404`, so the status code alone cannot tell the two reasons apart. The route table in item 9 can.

---

## Item 9: Both Hosts Are In The Route Table

> **Task item 9:** Both hosts appear in the gateway proxy's route table. A `VirtualService` that exists but is not bound to the gateway fails this check even though the objects look correct.

Read the route table of the gateway proxy:

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -E 'NAME|booking|catalog'
```

```text
NAME          VHOST NAME               DOMAINS               MATCH                  VIRTUAL SERVICE
http.8080     booking.ica.local:80     booking.ica.local     /book*                 booking.ingress-demo
http.8080     catalog.ica.local:80     catalog.ica.local     /items*                catalog.ingress-demo
```

Both hosts are there, each in its own virtual host, with their path matches and the `VirtualService` that produced the route. If a host is missing, its `VirtualService` never reached the gateway.

---

## Item 10: Both `VirtualService` Objects Name The Gateway

> **Task item 10:** Both `VirtualService` objects name the gateway in their `gateways` field.

```sh
kubectl -n ingress-demo get virtualservice -o custom-columns=NAME:.metadata.name,HOSTS:.spec.hosts,GATEWAYS:.spec.gateways
```

```text
NAME      HOSTS                 GATEWAYS
booking   [booking.ica.local]   [public-gateway]
catalog   [catalog.ica.local]   [public-gateway]
```

Both objects name `public-gateway`. The bare name is right, because the `Gateway` is in the same namespace, `ingress-demo`. A prefix such as `istio-system/public-gateway` would point at a `Gateway` that does not exist.

When you are done, stop the port forward with `kill %1`, or close the terminal.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-01
```

The grader sends the four requests through the gateway and reads the route table.

---

## Mistakes That Fail The Grader

- **Leaving out `gateways:` (items 3, 4, 9 and 10).** The routes go to `mesh`, the gateway answers `404`, and nothing reports an error. This is the most common failure here.
- **`hosts: ["*"]` on the `Gateway` (item 2).** It is convenient, but an unknown host is then not rejected, and item 7 fails.
- **One `VirtualService` that lists both hosts (items 3, 4 and 8).** Traffic would work, but `/book` and `/items` would be reachable under both host names, and item 8 fails.
- **`protocol: TCP` (item 2).** The gateway then does no routing by host or path at all.
- **A `selector` that matches no pod (item 1).** The `Gateway` exists but configures no proxy. `istioctl analyze` reports this one.
- **Forgetting `-H "Host: ..."` when you test (items 5 to 8).** The host `localhost:8080` matches no host on the listener.
- **Expecting an `EXTERNAL-IP` (Start).** `<pending>` is correct on `kind`.
