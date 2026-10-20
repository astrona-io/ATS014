# Solution Walkthrough

The lab has two faults, and the first one hides the second. As long as the sidecar proxy of `shuttle` sends requests direct, the broken `Gateway` never gets a chance to fail. An egress gateway is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. It carries only the requests that a `VirtualService` sends to it. The walkthrough fixes the faults in the order that the access logs show them. The first fix is the `VirtualService` (it answers task check 1). The second fix is the `Gateway` (it answers task check 4). Task checks 2 and 3 prove the result.

---

## Start: Look At The Symptom

The task says that the requests reach the relay without passing the egress gateway. Send a request from `shuttle`. Read the access log of its sidecar proxy, where the proxy writes one line for each request. Then count the lines for the relay in the access log of the egress gateway. The log lines are shortened to 230 characters:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
sleep 3
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-230
sleep 4
kubectl -n istio-egress logs deploy/istio-egress --tail=-1 | grep -c relay.outpost.example
```

```text
200
[2026-10-20T22:24:24.147Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 1134 1 0 "-" "curl/8.11.1" "6481c384-856e-4ef9-8cab-0616b2823a9b" "relay.outpost.example:8080" "10.244.0.8:8080" outbound|8080||relay.outpost.example 10.244
0
```

The relay answers `200`. But the log of the `shuttle` sidecar ends at `10.244.0.8:8080`, which is the relay pod itself, through the cluster `outbound|8080||relay.outpost.example`. A cluster is a named destination in Envoy. The egress gateway logged nothing. The request went direct and skipped the egress gateway, so the `200` proves nothing.

List the four objects, and print the `gateways` of the `VirtualService`. Save the state that the rules of the task say must stay:

```sh
kubectl -n starfleet get serviceentry,gateway,destinationrule,virtualservice
kubectl -n starfleet get virtualservice relay-via-departure-gate -o jsonpath='{.spec.gateways}{"\n"}'
kubectl -n starfleet get serviceentry relay -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get destinationrule departure-gate-for-relay -o jsonpath='generation={.metadata.generation} {.spec}{"\n"}'
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
```

```text
NAME                                     HOSTS                       LOCATION        RESOLUTION   AGE
serviceentry.networking.istio.io/relay   ["relay.outpost.example"]   MESH_EXTERNAL   STATIC       8s

NAME                                         AGE
gateway.networking.istio.io/departure-gate   8s

NAME                                                           HOST                                          AGE
destinationrule.networking.istio.io/departure-gate-for-relay   istio-egress.istio-egress.svc.cluster.local   8s

NAME                                                          GATEWAYS             HOSTS                       AGE
virtualservice.networking.istio.io/relay-via-departure-gate   ["departure-gate"]   ["relay.outpost.example"]   8s
["departure-gate"]
generation=1
generation=1 {"host":"istio-egress.istio-egress.svc.cluster.local","subsets":[{"name":"relay"}]}
NAME    UID
relay   7f939a30-30c0-4c84-9bc7-b9ed65247449
No resources found in outpost namespace.
```

---

## Fault 1: Hop 1 Never Runs

Hop 1 is the `VirtualService` rule that should send the request of `shuttle` to the egress gateway. The output above shows the cause. The top-level `gateways` list of the `VirtualService` names only the egress gateway, `departure-gate`. That list decides which proxies get the `VirtualService` at all. Without `mesh`, the reserved name for every sidecar proxy, `istiod`, the Istio control plane, gives it to no sidecar. So the hop 1 rule never runs, even though its own `match` says `mesh`.

Add `mesh` to the top-level list. Save this as `virtualservice-relay.yaml`:

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

```text
virtualservice.networking.istio.io/relay-via-departure-gate configured
```

Wait a few seconds for `istiod` to send the change. Send the request again, and read both access logs:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
sleep 3
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-230
kubectl -n istio-egress logs deploy/istio-egress --tail=1 | cut -c1-230
```

```text
404
[2026-10-20T22:24:40.080Z] "GET /get HTTP/1.1" 404 - via_upstream - "-" 0 0 3 2 "-" "curl/8.11.1" "fa6aa382-51fc-4c15-b3b6-302f41f211b4" "relay.outpost.example:8080" "10.244.0.6:80" outbound|80|relay|istio-egress.istio-egress.svc.
[2026-10-20T22:24:40.081Z] "GET /get HTTP/2" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.7" "curl/8.11.1" "e25b3de2-84cf-44b7-9fb3-3806cfa0fd19" "relay.outpost.example:8080" "-" - - 10.244.0.6:80 10.244.0.7:33070 - -
```

This is progress. Hop 1 reaches the pod of the egress gateway (`10.244.0.6:80`) through the subset `relay`. But the egress gateway answers `404` with the response flag `NR`, which means "no route". It received the request and has no route for `relay.outpost.example`. That is the second fault.

---

## Fault 2: The Egress Gateway Has No Route

Look at the route table of the egress gateway, the host list of the `Gateway`, and the analyzer:

```sh
istioctl proxy-config routes deploy/istio-egress -n istio-egress
kubectl -n starfleet get gateway departure-gate -o jsonpath='{.spec.servers[0].hosts}{"\n"}'
istioctl analyze -n starfleet 2>&1 | grep IST
```

```text
NAME        VHOST NAME       DOMAINS     MATCH                  VIRTUAL SERVICE
http.80     blackhole:80     *           /*                     404
            backend          *           /healthz/ready*        
            backend          *           /stats/prometheus*     
["istio-egress.istio-egress.svc.cluster.local"]
Warning [IST0132] (VirtualService starfleet/relay-via-departure-gate) one or more host [relay.outpost.example] defined in VirtualService starfleet/relay-via-departure-gate not found in Gateway starfleet/departure-gate.
```

Port `80` of the egress gateway has only the `blackhole` route, which answers `404`. The `Gateway` serves the own Service name of the egress gateway, and not the relay. A `VirtualService` attaches to a `Gateway` only for the hosts that the `Gateway` serves. So hop 2 never reached the egress gateway, and `IST0132` points at the same fault. Read the `Gateway` from the point of view of the egress gateway: for which host do I accept requests? The answer is the host name of the relay. Save this as `gateway-departure-gate.yaml`:

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

```text
gateway.networking.istio.io/departure-gate configured
```

---

## Check 1: The Route Of `shuttle` Points At The Egress Gateway

> **Task check 1:** The `shuttle` sidecar's route for `relay.outpost.example` on port `8080` points at the egress gateway Service, subset `relay`.

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8080 -o json | grep -o 'outbound|[^"]*' | sort -u
```

```text
outbound|80|relay|istio-egress.istio-egress.svc.cluster.local
```

The only destination in the route table of `shuttle` for port `8080` is the cluster of the egress gateway Service with the subset `relay`.

---

## Checks 2 And 3: The Request Passes The Egress Gateway

> **Task check 2:** `GET http://relay.outpost.example:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.
>
> **Task check 3:** The egress gateway's own access log gains a line for that request.

Count the lines of the egress gateway before and after one request. Wait before each count, because the proxy writes the log line a moment after the request:

```sh
sleep 4
BEFORE=$(kubectl -n istio-egress logs deploy/istio-egress --tail=-1 | grep -c relay.outpost.example)
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://relay.outpost.example:8080/get
sleep 4
AFTER=$(kubectl -n istio-egress logs deploy/istio-egress --tail=-1 | grep -c relay.outpost.example)
echo "egress gateway lines: +$((AFTER - BEFORE))"
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-230
kubectl -n istio-egress logs deploy/istio-egress --tail=1 | cut -c1-230
```

```text
200
egress gateway lines: +1
[2026-10-20T22:24:56.313Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 1326 7 6 "-" "curl/8.11.1" "5077a5a7-544b-4860-a65a-709908b827af" "relay.outpost.example:8080" "10.244.0.6:80" outbound|80|relay|istio-egress.istio-egress.s
[2026-10-20T22:24:56.313Z] "GET /get HTTP/2" 200 - via_upstream - "-" 0 1326 4 3 "10.244.0.7" "curl/8.11.1" "7a175bfb-2c1e-4306-9b28-e0289e4bc66c" "relay.outpost.example:8080" "10.244.0.8:8080" outbound|8080||relay.outpost.example
```

The request returns `200`, and the egress gateway logged one line. Hop 1 ends at the egress gateway (`10.244.0.6:80`), and hop 2 ends at the relay (`10.244.0.8:8080`). At the start, the egress gateway had no lines for the relay.

---

## Check 4: The `Gateway` Serves The Relay Host

> **Task check 4:** The `Gateway` `departure-gate` serves the host `relay.outpost.example`.

Print the hosts of the `Gateway`, read the route table of the egress gateway again, and let Istio check the namespace:

```sh
kubectl -n starfleet get gateway departure-gate -o jsonpath='{.spec.servers[0].hosts}{"\n"}'
istioctl proxy-config routes deploy/istio-egress -n istio-egress
istioctl analyze -n starfleet
```

```text
["relay.outpost.example"]
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     relay.outpost.example:80     relay.outpost.example     /*                     relay-via-departure-gate.starfleet
            backend                      *                         /healthz/ready*        
            backend                      *                         /stats/prometheus*     

✔ No validation issues found when analyzing namespace: starfleet.
```

The `Gateway` serves the relay host, the egress gateway has a route for it from `relay-via-departure-gate.starfleet`, and the analyzer reports no issue.

---

## What Must Not Change

> **Task rules:** Keep the object names. Fix the existing `Gateway` and `VirtualService`; do not add a second one of either kind in `starfleet`. The `ServiceEntry` `relay` and the `DestinationRule` `departure-gate-for-relay` are correct. Leave them in place. Leave the `relay` pod in `outpost` alone, and do not create a Service there.

```sh
kubectl -n starfleet get gateway,virtualservice -o name
kubectl -n starfleet get serviceentry relay -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get destinationrule departure-gate-for-relay -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
```

```text
gateway.networking.istio.io/departure-gate
virtualservice.networking.istio.io/relay-via-departure-gate
generation=1
generation=1
NAME    UID
relay   7f939a30-30c0-4c84-9bc7-b9ed65247449
No resources found in outpost namespace.
```

There is one `Gateway` and one `VirtualService`. The `ServiceEntry` and the `DestinationRule` still have `generation=1`, the relay pod has the same `UID`, and there is no Service in `outpost`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-080/module-01/labs/lab-02
```

The grader reads the route of `shuttle`, sends a request, and reads the access log of the egress gateway.

---

## Mistakes That Fail The Grader

- **Fixing only one fault.** With only `mesh` added, `shuttle` gets `404` with `NR` from the egress gateway. With only the `Gateway` fixed, `shuttle` still sends direct and the egress gateway logs nothing.
- **Removing the egress gateway from the route.** Deleting the `VirtualService` makes the relay answer `200`, but the log of the egress gateway stays empty, and the route of `shuttle` does not point at the egress gateway.
- **Creating a second `Gateway` or `VirtualService` instead of fixing the existing ones.**
- **Deleting the `DestinationRule`.** Hop 1 names the subset `relay`, and the subset would not exist any more.
- **Creating a Service in `outpost`.** That adds the relay to the service registry another way and skips the task.
