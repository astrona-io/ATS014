# Diagnose A Broken Egress `Gateway` Or `DestinationRule`

A route through the egress gateway needs more than a correct `VirtualService`. The **egress gateway** is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. Its `Gateway` must serve the outside host, and its `DestinationRule` must define the subset that the route names. This part breaks each of those two objects, shows what each break looks like in the access logs and in `istioctl analyze`, and ends with one table for every broken route.

## Two ways to break the supporting objects

An **access log** is the file where a proxy writes one line for each request or connection it handles. The **sidecar proxy** is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. After every change below, read the `shuttle` sidecar's access log: it shows where hop 1 went. In hop 1, the `shuttle` sidecar sends the request to the egress gateway; in hop 2, the egress gateway sends it to the internet.

The commands below need four objects in `starfleet` applied: the `ServiceEntry` `httpbin-org` (in `serviceentry-httpbin-org.yaml`), the `Gateway` `egress-gateway` (in `gateway-egress.yaml`), the `DestinationRule` `egress-gateway-for-httpbin-org` (in `destinationrule-egress-gateway.yaml`), and the working two-stage `VirtualService` `httpbin-org-via-egress`. The `Gateway` selects the pods labelled `istio: egress` and serves `httpbin.org` on port `443` with `tls.mode: PASSTHROUGH`. The `DestinationRule` defines the subset `httpbin-org`, with no labels, for the egress gateway's Service. A **subset** is a named group of a Service's pods, selected by labels. The `VirtualService` sends hop 1 to that subset and hop 2 to `httpbin.org` on port `443`.

<!-- astrona:playground:renew -->

Paste the helpers into your terminal first, if this terminal does not have them yet. `call_external` sends one request from `shuttle` and prints the status code, the time and the exit code of `curl`. `log_shuttle` and `log_gate` print the newest line of the `shuttle` sidecar's access log and of the egress gateway's access log:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

### Put the egress gateway's own name in the `Gateway`

The first break is the common first attempt: the egress gateway's Service name in `servers[].hosts` instead of the outside host.

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

Then send a request, read the `shuttle` sidecar's access log, and run `istioctl analyze`, the command that checks Istio objects for known mistakes:

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

The request fails. The **response flags**, the short codes in the access log that say why a request failed, are **`UF,URX`**: "the upstream connection failed" and "the retry limit was reached", with the reason `Connection_refused`. The egress gateway refuses the connection because it has no listener on `443`. A `VirtualService` only attaches to a `Gateway` for the hosts that the `Gateway` serves. `httpbin.org` is not among them, so hop 2 never reaches the egress gateway. This time `istioctl analyze` warns you, with **`IST0132`**.

Put the right `Gateway` back:

```sh
kubectl apply -f gateway-egress.yaml
```

### Delete the `DestinationRule`

The second break removes the subset. The `VirtualService` names the subset `httpbin-org`, and after this command nothing defines it:

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

Each broken object leaves its own pattern. There are four common breaks in total. Two are in the `VirtualService`: without `mesh` in its top-level `gateways`, the request skips the egress gateway and still returns `200`. Without the hop 2 rule, the egress gateway has no listener and refuses the connection. The two breaks in this part add the last patterns. Read the `shuttle` sidecar's log first, then the egress gateway's log:

| What you see | What broke |
| --- | --- |
| `200`, `shuttle` log ends at an internet address, egress gateway log empty | hop 1 never reached the sidecars: `mesh` missing from the top-level `gateways` |
| `000`, `shuttle` log `UF,URX` `Connection_refused` to the egress gateway's pod | the egress gateway has no listener: hop 2 missing, or the `Gateway` serves another host (`IST0132`) |
| `000`, `shuttle` log `NC` | the subset that hop 1 names does not exist: the `DestinationRule` is missing (`IST0101`) |
| `200`, `shuttle` log ends at the egress gateway's pod, egress gateway log ends at an internet address | everything works |

You can now name the broken object from the two access logs and from `istioctl analyze`, for every common way an egress route breaks. The open question is how to send only some workloads through the egress gateway, and what that choice really controls.

## Common pitfalls

> [!WARNING]
> - **Writing the egress gateway's own Service name in the `Gateway`.** `servers[].hosts` names the outside host, `httpbin.org`. Run `istioctl analyze` and look for `IST0132`.
> - **Deleting the `DestinationRule` because its subset has no labels.** Hop 1 names the subset, so without it the `shuttle` sidecar has no cluster (`NC`, `IST0101`).
> - **Expecting `istioctl analyze` to catch every break.** It warns about a `Gateway` that does not serve the host (`IST0132`) and a missing subset (`IST0101`). It reports nothing for a missing `mesh` or a missing hop 2.
> - **Looking for a refused request in the egress gateway's log.** When the egress gateway has no listener, it refuses the connection and writes nothing. The `shuttle` sidecar's log shows what happened.

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
