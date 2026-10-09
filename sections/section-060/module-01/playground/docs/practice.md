# Practice: Expose The Probe Through The Ingress Gateway

An exam-style mission for this playground, astronaut. Start the playground
first, and paste the `gateway_status` helper from
[overview.md](./overview.md#helper). The solution uses it.

Try the task on your own first, then open the solution. The solution was run
and checked on a real cluster.

## Task: open a second host at the gate

> Expose the `probe` Service (port `8000`) in namespace `starfleet` at the host
> **probe.example.com** through the ingress gateway. Only the paths `/get` and
> `/headers` may be reachable. Use a `Gateway` named `probe-gateway` and a
> `VirtualService` named `probe`. The bridge must stay reachable at
> `starfleet.example.com`.

<details><summary>Solution</summary>

The gate needs its own listener host, and the probe needs a flight plan linked
to it. Open the gate first.

Save this as `gateway-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: probe-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - probe.example.com
```

Apply it:

```bash
kubectl apply -f gateway-probe.yaml
```

Then write the flight plan. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe.example.com
  gateways:
  - probe-gateway
  http:
  - match:
    - uri:
        exact: /get
    - uri:
        exact: /headers
    route:
    - destination:
        host: probe
        port:
          number: 8000
```

Apply it:

```bash
kubectl apply -f virtualservice-probe.yaml
```

Then check the result: the two open paths, a closed path, and the bridge:

```bash
gateway_status /get probe.example.com
gateway_status /headers probe.example.com
gateway_status /status/200 probe.example.com
gateway_status /productpage
```

```text
200
200
404
200
```

The two `match` entries sit in separate list items, so either path is enough
(OR). Every other path finds no route at the gate and gets `404`. Both
`Gateway` objects share the same port `80` listener, and the gate tells them
apart by the `Host` header, so the bridge keeps working.

</details>
