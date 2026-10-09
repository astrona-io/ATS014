# Solution Walkthrough

Four objects, astronaut. Three are straightforward; the `VirtualService` is the one worth slowing down for, because it configures two different proxies from one document.

---

## Step 1: Confirm the Gateway Is Idle

```sh
PARTNER=$(cat /tmp/partner-ip); echo "partner: $PARTNER"
kubectl -n istio-system get pods -l istio=egressgateway
kubectl -n egwgw-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'direct call: %{http_code}\n' --max-time 10 "http://$PARTNER:8080/get"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner || echo 0
```

```text
partner: 10.244.0.19
NAME                                   READY   STATUS    AGE
istio-egressgateway-7f4b6d8c9d-2wnzq   1/1     Running   8m
direct call: 200
0
```

The departure gate is running. The call works. The gate's flight log recorded nothing — the signal went straight out through `tester`'s own communications officer (sidecar). **A deployed egress gateway is evidence of nothing.**

---

## Step 2: Register the Host

```sh
PARTNER=$(cat /tmp/partner-ip)
```

Replace `<PARTNER>` in the YAML below with the real address from the step above. To see it, run `echo $PARTNER`.

Save this as `serviceentry-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: egwgw-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - <PARTNER>
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PARTNER>
```

Apply it:

```sh
kubectl apply -f serviceentry-partner.yaml
```

The usual `ServiceEntry`: it puts the partner on the star chart. Without it neither stage below has a host to route.

---

## Step 3: Open the Gateway Listener

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

Save this as `egress-gateway-manifests.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: egwgw-demo
spec:
  selector:
    istio: egressgateway
  servers:
    - port:
        number: 8080
        name: http
        protocol: HTTP
      hosts:
        - partner.example.com
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-partner
  namespace: egwgw-demo
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: partner
```

Apply it:

```sh
kubectl apply -f egress-gateway-manifests.yaml
```

Two things that look wrong and are not:

- **`hosts: [partner.example.com]`** — the **external** hostname. Read the object from the gateway's point of view: it is going to receive requests whose `Host` header says `partner.example.com`, so that is what its listener must accept. An internal name here produces a gateway that rejects everything.
- **A subset with no labels.** It narrows nothing; it exists so the two stages can name a distinct cluster per external host. With several hosts through one gateway, each gets its own subset and the proxy configuration stays readable.

Note `selector: istio: egressgateway` — the **egress** gateway. Using `ingressgateway` here configures the wrong pod entirely.

---

## Step 4: The Two-Stage VirtualService

Save this as `virtualservice-partner-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-through-egress
  namespace: egwgw-demo
spec:
  hosts:
    - partner.example.com
  gateways:
    - mesh
    - egress-gateway
  http:
    - match:
        - port: 8080
          sourceLabels:
            egress-allowed: "true"
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: partner
            port:
              number: 8080
    - match:
        - gateways: [egress-gateway]
          port: 8080
      route:
        - destination:
            host: partner.example.com
            port:
              number: 8080
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-through-egress.yaml
```

One document, two rule sets, two proxies:

```text
  tester ──► its sidecar        stage 1 (gateways: [mesh]) runs here
                │  → istio-egressgateway.istio-system.svc
                ▼
          egress gateway        stage 2 (gateways: [egress-gateway]) runs here
                │  → partner.example.com
                ▼
          partner-api
```

The top-level `gateways` must list **both**. Omit `mesh` and stage 1 is never programmed into sidecars, so nothing is diverted; omit the gateway and stage 2 never arrives where it is needed.

---

## Step 5: Prove the Hop

The reply signal looks the same either way, so the evidence has to come from the gate's flight log:

```sh
PARTNER=$(cat /tmp/partner-ip)
BEFORE=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example.com)
kubectl -n egwgw-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'tester: %{http_code}\n' --max-time 15 "http://partner.example.com:8080/get"
sleep 3
AFTER=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example.com)
echo "gateway lines: +$((AFTER - BEFORE))"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=5 | grep partner.example.com | tail -1
```

```text
tester: 200
gateway lines: +1
[2026-09-27T13:22:41.006Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 3428 4 3 "10.244.0.28" "curl/8.5.0" "..." "partner.example.com" "10.244.0.19:8080" ...
```

One place, one line, with the calling pod's address in it. That log is the audit trail the whole arrangement exists to produce.

The structural confirmation is in the sidecar:

```sh
istioctl proxy-config routes deploy/tester -n egwgw-demo -o json | grep -i '"cluster"' | grep egress | head -1
```

```text
"cluster": "outbound|8080|partner|istio-egressgateway.istio-system.svc.cluster.local",
```

`tester`'s destination for the external host is now an in-cluster Service, with `|partner|` — the subset — in the cluster name.

---

## Step 6: See What `sourceLabels` Actually Does

```sh
PARTNER=$(cat /tmp/partner-ip)
BEFORE=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example.com)
kubectl -n egwgw-demo exec deploy/other-client -- \
  curl -s -o /dev/null -w 'other-client: %{http_code}\n' --max-time 15 "http://partner.example.com:8080/get"
sleep 3
AFTER=$(kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner.example.com)
echo "gateway lines: +$((AFTER - BEFORE))"
```

```text
other-client: 200
gateway lines: +0
```

This is the lesson. The `other-client` spaceship does not carry `egress-allowed: "true"`, so stage 1 did not apply — and it **still reached the endpoint**, directly, with no record at the gate.

`sourceLabels` narrows the **route**, not the permission. A non-matching workload is un-diverted, not blocked. To make the gateway a genuine control you need `REGISTRY_ONLY` so nothing unregistered leaves at all, plus an `AuthorizationPolicy` on the gateway.

---

## Common Mistakes

- **Expecting the gateway to intercept.** It carries nothing until routed to. The `+0` in step 1 is the proof.
- **An internal hostname in the `Gateway`'s `servers[].hosts`.** It must be the external host.
- **`selector: istio: ingressgateway`.** Wrong gateway — that one serves inbound traffic.
- **The two `match.gateways` values swapped.** Traffic loops or never diverts.
- **`mesh` missing from the top-level `gateways`.** Stage 1 never reaches sidecars.
- **No `ServiceEntry`.** Neither stage has a host to route.
- **Counting gateway log lines without a baseline.** The log accumulates.
- **Reading `sourceLabels` as an access control.** It is a route filter; non-matching workloads go direct.
