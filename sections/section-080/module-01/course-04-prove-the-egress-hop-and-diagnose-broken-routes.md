# Prove The Egress Hop And Diagnose Broken Routes

From the client's side, a route through the egress gateway looks exactly like no route at all: both return `200`. So a working status code does not tell you which path the request took. This part shows the evidence that the extra hop really happened. Then it breaks the route in four ways, so you can tell each failure by its access log.

## A `200` proves nothing

The egress gateway's own access log is the direct evidence. It is also the reason the whole setup exists: **one** log, not one per workload, records every request that leaves the cluster. After a working route, `log_gate` prints a line that ends in `outbound|443||httpbin.org`. Each line also contains the address of the pod that sent the request, so you know which workload called out.

Keep one habit for this whole part: **after every change, read the `shuttle` sidecar's access log too**. It shows where hop 1 went. A `200` at `shuttle` only says that *some* path worked.

The commands below need four objects in `starfleet` applied: the `ServiceEntry` `httpbin-org` (in `serviceentry-httpbin-org.yaml`), the `Gateway` `egress-gateway` (in `gateway-egress.yaml`), the `DestinationRule` `egress-gateway-for-httpbin-org` (in `destinationrule-egress-gateway.yaml`), and the working two-stage `VirtualService` `httpbin-org-via-egress` in `virtualservice-httpbin-org-via-egress.yaml`. That `VirtualService` lists `mesh` and `egress-gateway` in its top-level `gateways`, sends hop 1 to the egress gateway's subset `httpbin-org`, and sends hop 2 to `httpbin.org` on port `443`.

## Four ways to break the route

Each break below changes one object, reads the logs, and then puts the working object back. Together they cover the mistakes people make most often with egress gateways.

<!-- astrona:playground:renew -->

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

### Put the egress gateway's own name in the `Gateway`

The third break is the common first attempt: the egress gateway's Service name in `servers[].hosts` instead of the outside host.

Save this as `gateway-wrong-host.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 443
      name: tls
      protocol: TLS
    hosts:
    - istio-egress.istio-egress.svc.cluster.local
    tls:
      mode: PASSTHROUGH
```

Apply it:

```sh
kubectl apply -f gateway-wrong-host.yaml
```

Then send a request, read the `shuttle` sidecar's access log, and run `istioctl analyze`:

```sh
call_external
log_shuttle
istioctl analyze -n starfleet
```

You should see (trimmed):

```text
000 0.014547s
command terminated with exit code 35
  exit=35
"- - -" 0 UF,URX - - "delayed_connect_error:_Connection_refused" 0 0 3 - "-" "-" "-" "-" "10.244.0.6:443" outbound|443|httpbin-org|istio-egress.istio-egress.svc.cluster.local ... httpbin.org -
Warning [IST0132] (VirtualService starfleet/httpbin-org-via-egress) one or more host [httpbin.org] defined in VirtualService starfleet/httpbin-org-via-egress not found in Gateway starfleet/egress-gateway.
```

This is the same refusal as with a missing hop 2, for the same reason. A `VirtualService` only attaches to a `Gateway` for the hosts that the `Gateway` serves. `httpbin.org` is not among them, so hop 2 never reaches the egress gateway. This time `istioctl analyze` warns you, with **`IST0132`**.

Put the right `Gateway` back:

```sh
kubectl apply -f gateway-egress.yaml
```

### Delete the `DestinationRule`

The last break removes the subset. The `VirtualService` names the subset `httpbin-org`, and after this command nothing defines it:

```sh
kubectl delete -f destinationrule-egress-gateway.yaml
```

Then send a request, read the `shuttle` sidecar's access log, and run `istioctl analyze`:

```sh
call_external
log_shuttle
istioctl analyze -n starfleet
```

You should see (trimmed):

```text
000 0.018258s
command terminated with exit code 35
  exit=35
"- - -" 0 NC - - "-" 0 0 2 - "-" "-" "-" "-" "-" - - 98.88.155.171:443 ... httpbin.org -
Error [IST0101] (VirtualService starfleet/httpbin-org-via-egress) Referenced host+subset in destinationrule not found: "istio-egress.istio-egress.svc.cluster.local+httpbin-org"
```

The response flag **`NC`** means "no cluster". The `shuttle` sidecar has no cluster for the subset, so the request never leaves the pod. `istioctl analyze` names the missing subset with **`IST0101`**. The `DestinationRule` that looked pointless was holding up hop 1.

Put it back:

```sh
kubectl apply -f destinationrule-egress-gateway.yaml
```

## Reading the failures

The four breaks leave four different patterns. Read the `shuttle` sidecar's log first, then the egress gateway's log:

| What you see | What broke |
| --- | --- |
| `200`, `shuttle` log ends at an internet address, egress gateway log empty | hop 1 never reached the sidecars: `mesh` missing from the top-level `gateways` |
| `000`, `shuttle` log `UF,URX` `Connection_refused` to the egress gateway's pod | the egress gateway has no listener: hop 2 missing, or the `Gateway` serves another host (`IST0132`) |
| `000`, `shuttle` log `NC` | the subset that hop 1 names does not exist: the `DestinationRule` is missing (`IST0101`) |
| `200`, `shuttle` log ends at the egress gateway's pod, egress gateway log ends at an internet address | everything works |

You can now prove that a request passed through the egress gateway, and name the broken object from the two access logs. The open question is how to send only some workloads through the egress gateway, and what that choice really controls.

## Common pitfalls

> [!WARNING]
> - **Trusting a `200`.** With `mesh` missing, requests still succeed, straight out past the egress gateway. Read hop 1 in the `shuttle` sidecar's log.
> - **Expecting `istioctl analyze` to catch every break.** It warns about a `Gateway` that does not serve the host (`IST0132`) and a missing subset (`IST0101`). It reports nothing for a missing `mesh` or a missing hop 2.
> - **Looking for a refused request in the egress gateway's log.** When the egress gateway has no listener, it refuses the connection and writes nothing. The `shuttle` sidecar's log shows what happened.
> - **Counting egress gateway log lines without a baseline.** The log grows with every run. Read the newest line, or count before and after.

## Your mission: Fix An Egress Route That Skips The Gateway Lab

You can now prove a request passed through the egress gateway, and tell each broken route by its access log. In the lab, a route through the egress gateway is written and the outside endpoint answers, but the egress gateway's access log stays empty. You must find every fault and fix it.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-01/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-080-01-02
astrona start ats-014-playground-080-01
```
