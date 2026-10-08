# Practice – Circuit breaking

An exam-style training mission, astronaut, that combines both halves of circuit breaking (raising the shields and pulling damaged ships out of formation): the connection
pool from [module 2](../../../module-02/course.md) and outlier detection from
[this module](../../course.md).

Start the playground first (`astrona run -c .` in the `playground/` folder) and paste
the helpers from [`overview.md`](overview.md#helpers). The solution uses `load_test`.

Try it on your own first, then open the solution. The solution was run and checked
on a cluster set up like this playground.

> Limit callers of `httpbin` to **2** connections and **1** waiting request,
> one request per connection. Eject a pod for **30s** after **2** 5xx errors in
> a row, but never more than half of the pods. Prove the limit with fortio.

<details><summary>Solution</summary>

Write the rule to a file and apply it.

Save this as `destinationrule-httpbin-practice.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: httpbin, namespace: bookinfo}
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp: {maxConnections: 2}
      http: {http1MaxPendingRequests: 1, maxRequestsPerConnection: 1}
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

Apply it:

```bash
kubectl apply -f destinationrule-httpbin-practice.yaml
```

Then check the result:

```bash
load_test 5                    # Code 200 : 7 (23.3 %) / Code 503 : 23 (76.7 %)
load_test 1                    # Code 200 : 30 (100.0 %)
```

Five parallel connections overflow a pool of 2 connections plus 1 waiting slot, so
most requests get `503 UO`. One at a time never does.

</details>

## Exam cheat sheet

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: httpbin, namespace: bookinfo}
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1     # without this: no overflow
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5          # default 5 when the block exists; 0 = off
      consecutiveGatewayErrors: 0      # 502/503/504 only
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50           # default 10: too low for a small service
```

- Overflow = **503 `UO`** in the caller's access log; ejected pod = `OUTLIER CHECK FAILED`
  in `istioctl proxy-config endpoints`.
- Limits and ejections are per caller sidecar, not per service.
- Docs: istio.io → Tasks → Traffic Management →
  Circuit Breaking.
