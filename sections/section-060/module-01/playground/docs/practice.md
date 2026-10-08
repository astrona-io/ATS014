# Practice – Expose httpbin Through The Ingress Gateway

Astronaut, here is an exam-style training mission for this playground. It is not graded: you check your own
work. Start the playground first, and paste the `gateway_status` helper from
the [overview](overview.md#helper) into your terminal. The solution uses it.

```sh
astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-060/module-01/playground
```

Try it on your own first, then open the solution. The solution was run and
checked on a playground cluster.

> Expose `httpbin` (port 8000) at host **httpbin.example.com** through the
> ingress gateway. Only the paths `/get` and `/headers` may be reachable.

<details><summary>Solution</summary>

Write both objects to one file, then apply it:

```bash
cat > httpbin-gateway.yaml <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata: {name: httpbin-gateway, namespace: bookinfo}
spec:
  selector: {istio: ingress}
  servers:
  - port: {number: 80, name: http, protocol: HTTP}
    hosts: [httpbin.example.com]
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: httpbin, namespace: bookinfo}
spec:
  hosts: [httpbin.example.com]
  gateways: [httpbin-gateway]
  http:
  - match:
    - uri: {exact: /get}
    - uri: {exact: /headers}
    route:
    - destination: {host: httpbin, port: {number: 8000}}
YAML
kubectl apply -f httpbin-gateway.yaml
gateway_status /get httpbin.example.com          # 200
gateway_status /headers httpbin.example.com      # 200
gateway_status /status/200 httpbin.example.com   # 404
```

The two `match` entries sit in separate list items, so either path is enough
(OR). Every other path finds no route on the gateway and gets a 404.

</details>
