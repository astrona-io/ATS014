# Practice: Raise Both Shields

An exam-style training mission, astronaut, that combines both halves of a circuit breaker: raising the shields (a connection pool) and pulling damaged ships out of formation (outlier detection).

Start the playground first (`astrona run -c .` in the `playground/` folder) and paste
the helpers from [overview.md](./overview.md#helpers). The solution uses `load_test`.

Try it on your own first, then open the solution. The solution was run and checked
on a real cluster set up like this playground.

> Limit senders to the `probe` to **2** connections and **1** waiting signal,
> one signal per connection. Eject a ship for **30s** after **2** 5xx answers in
> a row, but never more than half of the ships. Prove the limit with fortio.

<details><summary>Solution</summary>

Both halves go in one `DestinationRule`, because two rules for one host do not combine reliably.

Save this as `destinationrule-probe-practice.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
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
kubectl apply -f destinationrule-probe-practice.yaml
```

Then check the result:

```bash
load_test 5
load_test 1
```

```text
Code 200 : 9 (30.0 %)
Code 503 : 21 (70.0 %)
Code 200 : 30 (100.0 %)
```

Five parallel connections overflow a pool of 2 connections plus 1 waiting slot, so
most signals are refused with `503 UO`. One at a time never is.

</details>

## Exam cheat sheet

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1     # without this: no overflow
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5          # 5 as soon as the block exists; 0 = off
      consecutiveGatewayErrors: 0      # 502/503/504 only
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50           # default 10: too low for a small service
```

- Overflow = **503 `UO`** in the sender's flight log; ejected ship = `OUTLIER CHECK FAILED`
  in `istioctl proxy-config endpoints`.
- Limits and ejections are per sender's proxy, not per service.
- A correct-looking rule that ejects nothing: read `ejections_overflow` first.
