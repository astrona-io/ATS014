# Practice – Egress Gateway

An exam-style mission for this playground, astronaut. Start the playground first and paste the helpers from [`overview.md`](overview.md) — the solution uses them.

Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Route HTTPS traffic to **www.google.com** through the egress gateway, the same way as `httpbin.org` in the module. Prove it in the egress gateway log.

<details><summary>Solution</summary>

Four objects, applied in "make before break" order: the host on the star chart, the gate, the subset, then the two-leg route.

Save this as `google-via-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata: {name: google, namespace: bookinfo}
spec:
  hosts: [www.google.com]
  ports: [{number: 443, name: tls, protocol: TLS}]
  location: MESH_EXTERNAL
  resolution: DNS
---
apiVersion: networking.istio.io/v1
kind: Gateway
metadata: {name: egress-google, namespace: bookinfo}
spec:
  selector: {istio: egress}
  servers:
  - port: {number: 443, name: tls, protocol: TLS}
    hosts: [www.google.com]
    tls: {mode: PASSTHROUGH}
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: egress-gateway-for-google, namespace: bookinfo}
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets: [{name: google}]
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: google-via-egress, namespace: bookinfo}
spec:
  hosts: [www.google.com]
  gateways: [mesh, egress-google]
  tls:
  - match: [{gateways: [mesh], port: 443, sniHosts: [www.google.com]}]
    route:
    - destination: {host: istio-egress.istio-egress.svc.cluster.local, subset: google, port: {number: 443}}
  - match: [{gateways: [egress-google], port: 443, sniHosts: [www.google.com]}]
    route:
    - destination: {host: www.google.com, port: {number: 443}}
```

Apply it:

```bash
kubectl apply -f google-via-egress.yaml
```

Then check the result:

```bash
call_external https://www.google.com     # 200
log_hop2_egress                         # ... outbound|443||www.google.com ...
```

</details>
