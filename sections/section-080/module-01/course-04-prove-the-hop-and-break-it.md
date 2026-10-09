# Prove The Hop, And Break It

Astronaut, a route through the departure gate looks exactly like no route at all from the shuttle's side: both answer `200`. This part gives you the evidence that the hop really happened, and then breaks the route four ways, so you know each failure by its flight log.

## A `200` proves nothing

The gate's own flight log is the direct evidence, and it is the reason the whole setup exists: **one** log, not one per ship, records every signal that leaves. In the last part, `log_gate` printed a line ending in `outbound|443||httpbin.org`. Each line also names the address of the ship that sent the signal, so you know who called out.

Keep one habit for this whole part: **after every change, read the shuttle's flight log too**. It tells you where hop 1 went. A `200` at the shuttle only says that *some* path worked.

The commands below need the four objects from the last parts applied: the `ServiceEntry`, the `Gateway`, the `DestinationRule` and the working `VirtualService` in `virtualservice-httpbin-org-via-egress.yaml`.

<!-- astrona:playground:renew -->

### Leave `mesh` out: it works, and skips the gate

Remove `mesh` from the top-level `gateways` list, and change nothing else. Save this as `virtualservice-without-mesh.yaml`:

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

Then send a signal, read the shuttle's flight log, and ask `istioctl analyze`:

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

A `200`, and a hop 1 that goes **straight out** to an internet address. The top-level `gateways` list decides which proxies get the flight plan at all. Without `mesh`, no sidecar gets it, so the hop 1 rule inside it never runs, even though it says `mesh` in its own `match`. The shuttle flies direct, which the `ServiceEntry` still allows. And `istioctl analyze` sees nothing wrong.

The object has the same name as the working one, so it replaced it. Put the working flight plan back:

```sh
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

### Leave out hop 2

Now keep only the hop 1 rule. The shuttle still sends the signal to the gate, but the gate has no orders for it. Save this as `virtualservice-missing-hop-2.yaml`:

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

Then send a signal, read the shuttle's flight log, and look at the gate's listeners:

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

Now it fails, and the logs tell you where:

- **The shuttle's log** shows hop 1 did its job: it went to the gate's subset. The response flags **`UF,URX`** mean "the upstream connection failed" and "the retry limit was reached". The reason is spelled out: `Connection_refused`.
- **The gate has no listener on `443`.** With no hop 2 rule, nothing tells the gate what to do with `httpbin.org`, so Istio builds no listener for it. The gate refuses the connection, and writes no line in its own flight log.

Put the working flight plan back:

```sh
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

### Put the gate's own name in the `Gateway`

The common first attempt from earlier: the gate's Service name in `servers[].hosts` instead of the outside host. Save this as `gateway-wrong-host.yaml`:

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

Then send a signal, read the shuttle's flight log, and ask `istioctl analyze`:

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

The same refusal as a missing hop 2, for the same reason: a `VirtualService` only attaches to a `Gateway` for the hosts the `Gateway` serves. `httpbin.org` is not among them, so hop 2 never reaches the gate. This time `istioctl analyze` warns you, with **`IST0132`**.

Put the right `Gateway` back:

```sh
kubectl apply -f gateway-egress.yaml
```

### Delete the `DestinationRule`

The last break: the flight plan names the subset `httpbin-org`, and nothing defines it any more. Delete the `DestinationRule`:

```sh
kubectl delete -f destinationrule-egress-gateway.yaml
```

Then send a signal, read the shuttle's flight log, and ask `istioctl analyze`:

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

The response flag **`NC`** means "no cluster": the shuttle's proxy has no cluster for the subset, so the signal never even leaves the ship. `istioctl analyze` names the missing subset with **`IST0101`**. The "pointless" `DestinationRule` was holding up hop 1.

Put it back:

```sh
kubectl apply -f destinationrule-egress-gateway.yaml
```

## Reading the failures

Four breaks, four fingerprints. Read the shuttle's log first, then the gate's:

| What you see | What broke |
| --- | --- |
| `200`, shuttle log ends at an internet address, gate log empty | hop 1 never reached the sidecars: `mesh` missing from the top-level `gateways` |
| `000`, shuttle log `UF,URX` `Connection_refused` to the gate's pod | the gate has no listener: hop 2 missing, or the `Gateway` serves another host (`IST0132`) |
| `000`, shuttle log `NC` | the subset hop 1 names does not exist: the `DestinationRule` is missing (`IST0101`) |
| `200`, shuttle log ends at the gate's pod, gate log ends at an internet address | everything works |

## Common pitfalls

> [!WARNING]
> - **Trusting a `200`.** With `mesh` missing, signals still succeed, straight out past the gate. Read hop 1 in the shuttle's log.
> - **Expecting `istioctl analyze` to catch every break.** It warns about a `Gateway` that does not serve the host (`IST0132`) and a missing subset (`IST0101`). It stays quiet about a missing `mesh` and a missing hop 2.
> - **Looking for a refused signal in the gate's log.** When the gate has no listener, it refuses the connection and writes nothing. The shuttle's log tells the story.
> - **Counting gate log lines without a baseline.** The log grows with every run. Read the newest line, or count before and after.

> *Read both flight logs. The shuttle's says where hop 1 went, the gate's says whether hop 2 happened.*

## Your mission: Repair The Departure Gate

You can now prove a signal flew through the gate, and tell each broken route by its flight log. Now prove it in a graded mission: a route through the departure gate is written, the relay answers, and still the gate's flight log stays empty. Find every fault and fix it.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-01/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-080-01-02
astrona start ats-014-playground-080-01
```
