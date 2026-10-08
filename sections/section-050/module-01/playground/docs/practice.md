# Practice – Fault Injection

An exam-style mission for you, astronaut. Start the playground first, and paste
the helper functions from [the overview](overview.md#helper-functions). The
solution uses them.

Try it on your own first, then open the solution. The solution was run and
checked on this environment.

> Requests from **productpage** to **details** must be delayed by **3 seconds**.
> Direct calls to details from other workloads must stay fast.

<details><summary>Solution</summary>

Write the VirtualService to a file:

```bash
cat > virtualservice-details.yaml <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: details, namespace: bookinfo}
spec:
  hosts: [details]
  http:
  - match:
    - sourceLabels: {app: productpage}
    fault:
      delay: {percentage: {value: 100}, fixedDelay: 3s}
    route:
    - destination: {host: details}
  - route:
    - destination: {host: details}
YAML
```

Apply it and check both paths:

```bash
kubectl apply -f virtualservice-details.yaml
status_and_time http://details:9080/details/0           # 200 0.01s  (curl → details: fast)
status_and_time http://productpage:9080/productpage     # 200 3.0s   (productpage → details: slow)
```

No DestinationRule is needed: the route uses the service without a subset.

`sourceLabels` matches the labels of the pod that *sends* the request. The
delay runs in `productpage`'s sidecar, so only its calls to `details` slow down.

</details>
