# Solution Walkthrough

You need three objects: one `Gateway`, which opens the listener, and two `VirtualService` objects, which hold the routes for each host. One line in each `VirtualService`, the `gateways:` field, decides whether any of it works.

---

## Step 1: Set Up Access And See The Starting State

Look at the gateway pod, the Istio objects and the listeners of the gateway proxy:

```sh
kubectl -n istio-system get pods -l istio=ingressgateway
kubectl -n ingress-demo get gateway,virtualservice
istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system
```

```text
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-7f54444996-gg6kb   1/1     Running   0          25s
No resources found in ingress-demo namespace.
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

The pod is `1/1`: an Envoy proxy with no application container. It is healthy, but it has only its health and metrics listeners. No `Gateway` configures it yet, so nothing listens on port `8080`, the container port behind the Service's port `80`.

`kind` has no load balancer, so the gateway Service never gets an `EXTERNAL-IP`, and you reach it with `kubectl port-forward`. Do not start the port forward yet. With no listener on port `8080`, the first request gets an empty reply (curl prints `000`), and `kubectl port-forward` stops with `error: lost connection to pod`.

---

## Step 2: Open The Listener

Write the `Gateway` to a file and apply the file. On the exam this habit pays off: you can read the file again, edit it and apply it again. Save this as `gateway-public-gateway.yaml`:

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

The gateway proxy now has a listener on port `8080`, so start the port forward:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080
```

The grader checks three things in this object:

- **`selector: istio: ingressgateway`** is a pod label selector. It matches the gateway pods that the `demo` profile installed. A selector that matches no pod gives an object that configures no proxy.
- **`protocol: HTTP`** lets the gateway route by host and path. `TCP` would only forward bytes and ignore every HTTP rule you write.
- **Both hosts are listed, and there is no `*`.** The listener must reject unknown hosts, so a `*` fails check 7.

The `Gateway` lives in `ingress-demo`, while the pod it configures lives in `istio-system`. That split is normal: the selector is the only link between them.

Send a first request:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
404
```

This is expected. The listener exists now, but it has no routes, so the gateway answers `404`.

---

## Step 3: Bind Both VirtualServices

Each host gets its own `VirtualService`, bound to the same `Gateway`. Save this as `virtualservice-booking.yaml`:

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

Then save this as `virtualservice-catalog.yaml`:

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

Then check the result:

```sh
istioctl analyze -n ingress-demo
```

```text
✔ No validation issues found when analyzing namespace: ingress-demo.
```

**`gateways: [public-gateway]` is the key line.** Without it, the routes go to `mesh`, which means all sidecar proxies. The gateway keeps answering `404`, and `istioctl analyze` stays clean, because a `VirtualService` that is not bound to a gateway is still a valid object.

Each `VirtualService` names only its own host. Both use the same listener. The host list on each `VirtualService` keeps their routes apart.

---

## Step 4: Confirm The Routes Reached The Gateway

This check tells "my routes are wrong" apart from "my routes are not there". Read the gateway's route table and keep only the lines for your two hosts:

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -E 'booking|catalog'
```

```text
http.8080     booking.ica.local:80     booking.ica.local     /book*                 booking.ingress-demo
http.8080     catalog.ica.local:80     catalog.ica.local     /items*                catalog.ingress-demo
```

The columns are `NAME`, `VHOST NAME`, `DOMAINS`, `MATCH` and `VIRTUAL SERVICE`; `grep` removed the header line. Both hosts are there, each in its own virtual host, with their path matches and the `VirtualService` that produced each route. If a host is missing here, its `VirtualService` never reached the gateway.

---

## Step 5: Verify All Four Cases

Send the four requests that the grader sends:

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

The last two requests fail for different reasons. `unknown.ica.local` matched no host on the listener, so the gateway had no routes for it. `catalog.ica.local /book` matched a host on the listener, but found no route for that path under that host: the `catalog` `VirtualService` only matches `/items`.

Both answers are `404`, so the status code alone cannot tell them apart. That is why the route table in step 4 matters.

---

## Common Mistakes

- **Leaving out `gateways:`.** The routes go to `mesh`, the gateway answers `404`, and nothing reports an error. This is the most common failure here.
- **`hosts: ["*"]` on the `Gateway`.** It is convenient, but it fails the check that an unknown host is rejected.
- **One `VirtualService` that lists both hosts.** Traffic would work, but then `/book` and `/items` are reachable under both host names, and check 8 fails.
- **`protocol: TCP`.** The gateway then does no routing by host or path at all.
- **A `selector` that matches no pod.** The `Gateway` exists but configures no proxy. `istioctl analyze` reports this one.
- **Forgetting `-H "Host: ..."` when testing.** Without it, curl sends `localhost:8080` as the host, which matches no host on the listener.
- **Expecting an `EXTERNAL-IP`.** `<pending>` is correct on `kind`.
- **Referring to the gateway as `istio-system/public-gateway`.** The `Gateway` object is in `ingress-demo`, so the bare name is right here. A namespace prefix would point at a `Gateway` that does not exist.
