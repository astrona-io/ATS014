# Solution Walkthrough

Two faults, astronaut, one on top of the other. The first hides the second: as long as the shuttle flies direct, the gate's broken setup never gets a chance to fail. Fix them in the order the flight logs reveal them.

---

## Step 1: Look At The Symptom

Send a signal to the relay, read the shuttle's flight log, and count the lines for the relay in the gate's flight log:

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

The relay answers `200`. But the shuttle's log ends at `10.244.0.8:8080`, the relay itself, through the cluster `outbound|8080||relay.outpost.example`. And the gate logged nothing. The signal flew direct, past the gate. A `200` proves nothing.

---

## Step 2: Find Out Why Hop 1 Never Runs

Hop 1 is the rule that should send the shuttle's signal to the gate. Look at which proxies the flight plan is for:

```sh
kubectl get virtualservice relay-via-departure-gate -n starfleet -o jsonpath='{.spec.gateways}{"\n"}'
```

```text
["departure-gate"]
```

Only the gate. The top-level `gateways` list decides which proxies get the flight plan at all. Without `mesh`, no sidecar gets it, so the hop 1 rule never runs, even though its own `match` says `mesh`.

Fix the flight plan. Save this as `virtualservice-relay.yaml`:

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

Then send the signal again and read both flight logs:

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

Progress: hop 1 now reaches the gate's pod (`10.244.0.6:80`), through the subset `relay`. But the gate answers `404` with the flag **`NR`**: "no route". The gate received the signal and has no orders for `relay.outpost.example`.

---

## Step 3: Find Out Why The Gate Has No Route

Look at the gate's routes and at the host list of the `Gateway`:

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

The gate's port `80` has only the `blackhole` route that answers `404`. And the `Gateway` serves the gate's own Service name, not the relay. A `VirtualService` only attaches to a `Gateway` for hosts the `Gateway` serves, so hop 2 never reached the gate. `istioctl analyze -n starfleet` points at the same fault with `IST0132`.

Read the `Gateway` from the gate's point of view: *which host will I serve?* The relay. Save this as `gateway-departure-gate.yaml`:

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

## Step 4: Prove The Signal Flies Through The Gate

Send the signal and read both flight logs again:

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

Hop 1 ends at the gate, hop 2 at the relay. Check the orders in both proxies too:

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

The gate has a route for the relay, the shuttle's route points at the gate's subset, and `istioctl analyze` is clean. Submit.

---

## Mistakes That Fail The Grader

- **Fixing only one fault.** With only `mesh` added, the shuttle gets `404 NR` from the gate. With only the `Gateway` fixed, the shuttle still flies direct and the gate logs nothing.
- **Removing the gate from the route.** Deleting the `VirtualService` makes the relay answer `200`, but the gate's log stays empty, and the shuttle's route does not point at the gate.
- **Creating a second `Gateway` or `VirtualService`** instead of fixing the existing ones.
- **Deleting the `DestinationRule`.** Hop 1 names the subset `relay`. Without it, the shuttle gets `503` with `NC`.
- **Creating a Service in `outpost`.** That puts the relay on the star chart through the back door.
