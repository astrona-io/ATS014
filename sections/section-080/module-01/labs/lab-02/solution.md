# Solution Walkthrough

The lab has two faults, and the first one hides the second. As long as the `shuttle` sidecar sends requests direct, the broken `Gateway` never gets a chance to fail. Fix them in the order the access logs show them.

---

## Step 1: Look At The Symptom

Send a request to the relay, read the `shuttle` sidecar's access log, and count the lines for the relay in the egress gateway's access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
kubectl logs -n istio-egress deploy/istio-egress --tail=-1 | grep -c relay.outpost.example
```

You should see (log line trimmed):

```text
200
"GET /get HTTP/1.1" 200 - via_upstream - "-" 0 1134 8 2 "-" "curl/8.11.1" "..." "relay.outpost.example:8080" "10.244.0.8:8080" outbound|8080||relay.outpost.example ...
0
```

The relay answers `200`. But the `shuttle` sidecar's log ends at `10.244.0.8:8080`, the relay pod itself, through the cluster `outbound|8080||relay.outpost.example`. And the egress gateway logged nothing. The request went direct and skipped the egress gateway, so the `200` proves nothing.

---

## Step 2: Find Out Why Hop 1 Never Runs

Hop 1 is the `VirtualService` rule that should send the `shuttle` pod's request to the egress gateway. Check which proxies the `VirtualService` is for:

```sh
kubectl get virtualservice relay-via-departure-gate -n starfleet -o jsonpath='{.spec.gateways}{"\n"}'
```

```text
["departure-gate"]
```

It names only the egress gateway. The top-level `gateways` list decides which proxies get the `VirtualService` at all. Without `mesh`, the reserved name for every sidecar proxy, `istiod` gives it to no sidecar. So the hop 1 rule never runs, even though its own `match` says `mesh`.

Fix the `VirtualService` by adding `mesh` to the top-level list. Save this as `virtualservice-relay.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: relay-via-departure-gate
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  gateways:
  - mesh
  - departure-gate
  http:
  - match:
    - gateways:
      - mesh
      port: 8080
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: relay
        port:
          number: 80
  - match:
    - gateways:
      - departure-gate
      port: 80
    route:
    - destination:
        host: relay.outpost.example
        port:
          number: 8080
```

Apply it:

```sh
kubectl apply -f virtualservice-relay.yaml
```

Then send the request again and read both access logs:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
kubectl logs -n istio-egress deploy/istio-egress --tail=1
```

You should see (log lines trimmed):

```text
404
"GET /get HTTP/1.1" 404 - via_upstream - ... "relay.outpost.example:8080" "10.244.0.6:80" outbound|80|relay|istio-egress.istio-egress.svc.cluster.local ...
"GET /get HTTP/2" 404 NR route_not_found - ... "relay.outpost.example:8080" "-" - - 10.244.0.6:80 10.244.0.7:36570 - -
```

This is progress. Hop 1 now reaches the egress gateway's pod (`10.244.0.6:80`), through the subset `relay`. But the egress gateway answers `404` with the response flag **`NR`**, which means "no route". The egress gateway received the request and has no route for `relay.outpost.example`.

---

## Step 3: Find Out Why The Egress Gateway Has No Route

Look at the egress gateway's routes and at the host list of the `Gateway`:

```sh
istioctl proxy-config routes deploy/istio-egress -n istio-egress
kubectl get gateway.networking.istio.io departure-gate -n starfleet -o jsonpath='{.spec.servers[0].hosts}{"\n"}'
```

```text
NAME        VHOST NAME       DOMAINS     MATCH                  VIRTUAL SERVICE
http.80     blackhole:80     *           /*                     404
            backend          *           /stats/prometheus*
            backend          *           /healthz/ready*
["istio-egress.istio-egress.svc.cluster.local"]
```

Port `80` of the egress gateway has only the `blackhole` route, which answers `404`. And the `Gateway` serves the egress gateway's own Service name, not the relay. A `VirtualService` only attaches to a `Gateway` for the hosts that the `Gateway` serves, so hop 2 never reached the egress gateway. `istioctl analyze -n starfleet` points at the same fault with `IST0132`.

Read the `Gateway` from the egress gateway's point of view: *for which host do I accept requests?* The answer is the relay's host name. Save this as `gateway-departure-gate.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - relay.outpost.example
```

Apply it:

```sh
kubectl apply -f gateway-departure-gate.yaml
```

---

## Step 4: Prove The Request Passes The Egress Gateway

Send the request and read both access logs again:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
kubectl logs -n istio-egress deploy/istio-egress --tail=1
```

You should see (log lines trimmed):

```text
200
"GET /get HTTP/1.1" 200 - via_upstream - ... "relay.outpost.example:8080" "10.244.0.6:80" outbound|80|relay|istio-egress.istio-egress.svc.cluster.local ...
"GET /get HTTP/2" 200 - via_upstream - ... "relay.outpost.example:8080" "10.244.0.8:8080" outbound|8080||relay.outpost.example 10.244.0.6:51046 10.244.0.6:80 10.244.0.7:36578 - -
```

Hop 1 ends at the egress gateway, and hop 2 ends at the relay. Check the configuration in both proxies too:

```sh
istioctl proxy-config routes deploy/istio-egress -n istio-egress
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8080 -o json | grep -o 'outbound|[^"]*' | sort -u
istioctl analyze -n starfleet
```

```text
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     relay.outpost.example:80     relay.outpost.example     /*                     relay-via-departure-gate.starfleet
            backend                      *                         /stats/prometheus*
            backend                      *                         /healthz/ready*
outbound|80|relay|istio-egress.istio-egress.svc.cluster.local

✔ No validation issues found when analyzing namespace: starfleet.
```

The egress gateway has a route for the relay, the `shuttle` sidecar's route points at the egress gateway's subset, and `istioctl analyze` reports no issues. Submit the lab.

---

## Mistakes That Fail The Grader

- **Fixing only one fault.** With only `mesh` added, `shuttle` gets `404 NR` from the egress gateway. With only the `Gateway` fixed, `shuttle` still sends direct and the egress gateway logs nothing.
- **Removing the egress gateway from the route.** Deleting the `VirtualService` makes the relay answer `200`, but the egress gateway's log stays empty, and the `shuttle` sidecar's route does not point at the egress gateway.
- **Creating a second `Gateway` or `VirtualService`** instead of fixing the existing ones.
- **Deleting the `DestinationRule`.** Hop 1 names the subset `relay`. Without it, `shuttle` gets `503` with `NC`.
- **Creating a Service in `outpost`.** That adds the relay to the service registry another way and skips the task.
