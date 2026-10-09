# Prove The Egress Hop And Find Broken `VirtualService` Rules

From the client's side, a route through the egress gateway looks exactly like no route at all: both return `200`. The **egress gateway** is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. Because a working status code does not tell you which path the request took, you need other evidence. This part shows where that evidence is, and then breaks the two-stage `VirtualService` in two ways, so you can tell each mistake by its access log.

## A `200` proves nothing

An **access log** is the file where a proxy writes one line for each request or connection it handles. The egress gateway's own access log is the direct evidence that a request passed through it. It is also the reason the whole setup exists: **one** log, not one per workload, records every request that leaves the cluster. After a working route, `log_gate` prints a line that ends in `outbound|443||httpbin.org`. Each line also contains the address of the pod that sent the request, so you know which workload called out.

Keep one habit for this whole part: **after every change, read the `shuttle` sidecar's access log too**. The **sidecar proxy** is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. Its log shows where hop 1 went. A `200` at `shuttle` only says that *some* path worked.

The commands below need four objects in `starfleet` applied: the `ServiceEntry` `httpbin-org` (in `serviceentry-httpbin-org.yaml`), the `Gateway` `egress-gateway` (in `gateway-egress.yaml`), the `DestinationRule` `egress-gateway-for-httpbin-org` (in `destinationrule-egress-gateway.yaml`), and the working two-stage `VirtualService` `httpbin-org-via-egress` in `virtualservice-httpbin-org-via-egress.yaml`. That `VirtualService` lists `mesh` and `egress-gateway` in its top-level `gateways`, sends hop 1 to the egress gateway's subset `httpbin-org`, and sends hop 2 to `httpbin.org` on port `443`. In hop 1, the `shuttle` sidecar sends the request to the egress gateway; in hop 2, the egress gateway sends it to the internet.

## Two ways to break the `VirtualService`

Each break below changes the `VirtualService`, reads the logs, and then puts the working object back. Both are mistakes people often make when they write the two-stage route by hand.

<!-- astrona:playground:renew -->

Paste the helpers into your terminal first, if this terminal does not have them yet. `call_external` sends one request from `shuttle` and prints the status code, the time and the exit code of `curl`. `log_shuttle` and `log_gate` print the newest line of the `shuttle` sidecar's access log and of the egress gateway's access log:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

### Leave `mesh` out: the request works and skips the egress gateway

The first break removes `mesh` from the top-level `gateways` list and changes nothing else.

Save this as `virtualservice-without-mesh.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-org-via-egress
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  gateways:
  - egress-gateway
  tls:
  - match:
    - gateways:
      - mesh
      port: 443
      sniHosts:
      - httpbin.org
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: httpbin-org
        port:
          number: 443
  - match:
    - gateways:
      - egress-gateway
      port: 443
      sniHosts:
      - httpbin.org
    route:
    - destination:
        host: httpbin.org
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-without-mesh.yaml
```

Then send a request, read the `shuttle` sidecar's access log, and run `istioctl analyze`, the command that checks Istio objects for known mistakes:

```sh
call_external
log_shuttle
istioctl analyze -n starfleet
```

You should see (trimmed):

```text
200 0.508964s
  exit=0
"- - -" 0 - - - "-" 901 4875 623 - "-" "-" "-" "-" "3.225.83.162:443" outbound|443||httpbin.org ... httpbin.org -
✔ No validation issues found when analyzing namespace: starfleet.
```

The status is `200`, and hop 1 goes **straight out** to an internet address. The top-level `gateways` list decides which proxies get the `VirtualService` at all. Without `mesh`, `istiod` gives it to no sidecar, so the hop 1 rule never runs, even though its own `match` says `mesh`. The `shuttle` sidecar sends the request direct, which the `ServiceEntry` still allows. And `istioctl analyze` reports nothing wrong.

The object has the same name as the working one, so it replaced it. Put the working `VirtualService` back:

```sh
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

### Leave out hop 2

The second break keeps only the hop 1 rule. The `shuttle` sidecar still sends the request to the egress gateway, but the egress gateway has no rule for it.

Save this as `virtualservice-missing-hop-2.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-org-via-egress
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  gateways:
  - mesh
  - egress-gateway
  tls:
  - match:
    - gateways:
      - mesh
      port: 443
      sniHosts:
      - httpbin.org
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: httpbin-org
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-missing-hop-2.yaml
```

Then send a request, read the `shuttle` sidecar's access log, and look at the egress gateway's listeners:

```sh
call_external
log_shuttle
istioctl proxy-config listener deploy/istio-egress -n istio-egress
```

You should see (log line trimmed):

```text
000 0.016715s
command terminated with exit code 35
  exit=35
"- - -" 0 UF,URX - - "delayed_connect_error:_Connection_refused" 0 0 1 - "-" "-" "-" "-" "10.244.0.6:443" outbound|443|httpbin-org|istio-egress.istio-egress.svc.cluster.local ... httpbin.org -
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

Now the request fails, and the logs show where. The `shuttle` sidecar's log shows that hop 1 did its job: it went to the egress gateway's subset. The **response flags**, the short codes in the access log that say why a request failed, are **`UF,URX`**. `UF` means "the upstream connection failed", and `URX` means "the retry limit was reached". The log also gives the reason: `Connection_refused`.

The egress gateway has no listener on `443`. With no hop 2 rule, nothing tells the egress gateway what to do with `httpbin.org`, so `istiod` builds no listener for it. The egress gateway refuses the connection and writes no line in its own access log.

Put the working `VirtualService` back:

```sh
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

## Reading the two failures

The two breaks leave two different patterns. Read the `shuttle` sidecar's log first, then the egress gateway's log:

| What you see | What broke |
| --- | --- |
| `200`, `shuttle` log ends at an internet address, egress gateway log empty | hop 1 never reached the sidecars: `mesh` missing from the top-level `gateways` |
| `000`, `shuttle` log `UF,URX` `Connection_refused` to the egress gateway's pod, no egress gateway listener on `443` | hop 2 missing from the `VirtualService` |
| `200`, `shuttle` log ends at the egress gateway's pod, egress gateway log ends at an internet address | everything works |

You can now prove that a request passed through the egress gateway, and you can tell a missing `mesh` from a missing hop 2 by the two access logs. The `VirtualService` is not the only object that can break the route, though. The open question is what happens when the `Gateway` or the `DestinationRule` is wrong.

## Common pitfalls

> [!WARNING]
> - **Trusting a `200`.** With `mesh` missing, requests still succeed, straight out past the egress gateway. Read hop 1 in the `shuttle` sidecar's log.
> - **Expecting `istioctl analyze` to catch these breaks.** It reports nothing for a missing `mesh` or a missing hop 2.
> - **Looking for a refused request in the egress gateway's log.** When the egress gateway has no listener, it refuses the connection and writes nothing. The `shuttle` sidecar's log shows what happened.
> - **Counting egress gateway log lines without a baseline.** The log grows with every run. Read the newest line, or count before and after.
