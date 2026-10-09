# Solution Walkthrough

The solution has two objects and four features. In three places, one setting only works if another setting is right too. Build the `VirtualService` first, then the `DestinationRule`, then check each feature on its own.

---

## Step 1: See the Starting State

```sh
kubectl -n payments get pods -o wide
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 30 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
```

```text
ledger-bad-...    1/1   Running   10.244.0.24
ledger-good-...   1/1   Running   10.244.0.22
ledger-good-...   1/1   Running   10.244.0.23
fortio-...        2/2   Running   10.244.0.25
Code 200 : 20 (66.7 %)
Code 503 : 10 (33.3 %)
```

There are three endpoints, and one of them is broken. All three ledger pods show `1/1` `Running`, so Kubernetes reports no problem. One request in three fails.

---

## Step 2: Do the Budget Arithmetic

Before writing the read rule:

```text
attempts: 2  →  2 retries + 1 original  =  3 attempts
3 × perTryTimeout 1s                    =  3s minimum
plus headroom                           →  timeout: 4s
```

`4s` passes the grader's `(attempts + 1) × perTryTimeout` check with one second to spare. `3s` would be exactly at the limit and leaves no time to open connections. `2s` cuts off the retries.

---

## Step 3: The VirtualService, Writes First

Write the manifest to a file and apply the file. On the exam this habit pays off: you can read the file again, edit it and apply it again.

Save this as `virtualservice-ledger.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: ledger
  namespace: payments
spec:
  hosts:
    - ledger
  http:
    - match:
        - method:
            exact: POST
      route:
        - destination:
            host: ledger
            port:
              number: 8000
      timeout: 3s
      retries:
        attempts: 0
    - route:
        - destination:
            host: ledger
            port:
              number: 8000
      timeout: 4s
      retries:
        attempts: 2
        perTryTimeout: 1s
        retryOn: gateway-error
```

Apply it:

```sh
kubectl apply -f virtualservice-ledger.yaml
```

Two details that fail the task if wrong:

- **`attempts: 0`, not a missing block.** Without a `retries` block, Istio's default of 2 retries on connection failures still applies. For a payment, a retry is a duplicate.
- **`retryOn: gateway-error`, not `5xx`.** The next step adds a connection pool, and the proxy answers a pool rejection with a `503`. With `5xx`, the proxy would retry those rejections and add more concurrent requests to a pool that is already full.

---

## Step 4: The DestinationRule, All Three Policies

Save this as `destinationrule-ledger.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: ledger
  namespace: payments
spec:
  host: ledger
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 2
      http:
        http1MaxPendingRequests: 2
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
    loadBalancer:
      localityLbSetting:
        enabled: true
```

Apply it:

```sh
kubectl apply -f destinationrule-ledger.yaml
```

Then check the result:

```sh
istioctl analyze -n payments
```

```text
destinationrule.networking.istio.io/ledger created
✔ No validation issues found when analyzing namespace: payments.
```

Look at `maxEjectionPercent` again. With three endpoints, the 10% default gives `0.3`, which rounds down to zero. You need at least 34 to eject one endpoint. `100` is right here, because one of the three is really broken and you want the proxy to avoid it completely.

`localityLbSetting` is the easy part. Note that it only has an effect *because* `outlierDetection` is in the same `trafficPolicy`.

---

## Step 5: Verify the Retry Asymmetry

```sh
for method in GET POST; do
  BEFORE=$(kubectl -n payments logs -l app=ledger -c istio-proxy --tail=-1 | grep -c /status/503)
  kubectl -n payments exec deploy/fortio -c fortio -- \
    fortio curl -quiet -X "$method" http://ledger:8000/status/503 >/dev/null 2>&1
  sleep 3
  AFTER=$(kubectl -n payments logs -l app=ledger -c istio-proxy --tail=-1 | grep -c /status/503)
  echo "$method attempts: $((AFTER - BEFORE))"
done
```

```text
GET attempts: 3
POST attempts: 1
```

The path and the status are the same, only the method differs. The `GET` request reached the service three times and the `POST` request once, because the method match sent them to different rules.

---

## Step 6: Verify the Connection Pool

```sh
BEFORE=$(kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep 'ledger.*pending_overflow' | awk -F': ' '{print $2}')
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 8 -qps 0 -n 80 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
AFTER=$(kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep 'ledger.*pending_overflow' | awk -F': ' '{print $2}')
echo "pending_overflow +$((AFTER - BEFORE))"
kubectl -n payments logs deploy/fortio -c istio-proxy --tail=100 | grep -c ' 503 UO '
```

```text
Code 200 : 54 (67.5 %)
Code 503 : 26 (32.5 %)
pending_overflow +19
19
```

Eight concurrent clients send requests to a pool of two connections plus two pending requests. The proxy rejected nineteen requests with the `UO` flag. The `503` count is higher than that, because some `503` responses came from the broken replica. So one run has two different causes of `503`, and only the response flag tells them apart.

---

## Step 7: Verify the Ejection

```sh
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 2 -qps 0 -n 80 -loglevel Warning http://ledger:8000/get >/dev/null 2>&1
sleep 6
kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'ledger.*ejections_(active|total)'
istioctl proxy-config endpoints deploy/fortio -n payments \
  --cluster "outbound|8000||ledger.payments.svc.cluster.local"
```

```text
cluster.outbound|8000||ledger...outlier_detection.ejections_active: 1
cluster.outbound|8000||ledger...outlier_detection.ejections_total: 1
ENDPOINT            STATUS    OUTLIER CHECK   CLUSTER
10.244.0.22:8080    HEALTHY   OK              outbound|8000||ledger...
10.244.0.23:8080    HEALTHY   OK              outbound|8000||ledger...
10.244.0.24:8080    HEALTHY   FAILED          outbound|8000||ledger...
```

`10.244.0.24` is `ledger-bad`. Its `STATUS` is still `HEALTHY`, because that column comes from Kubernetes readiness. Its `OUTLIER CHECK` is `FAILED`, because the `fortio` proxy ejected it.

Note one more thing. The retries on the read rule hid most of these failures from the client the whole time. Outlier detection still counted every one of them, because it looks at each attempt, not at the result the client sees. So retries and outlier detection work well together.

Confirm the ledger is now healthy and nothing was removed:

```sh
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 40 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
kubectl -n payments get endpoints ledger
```

```text
Code 200 : 40 (100.0 %)
NAME     ENDPOINTS                                               AGE
ledger   10.244.0.22:8080,10.244.0.23:8080,10.244.0.24:8080      18m
```

---

## Common Mistakes

- **`retryOn: 5xx` with a connection pool.** Pool rejections are `503` responses, and retrying them adds more concurrent requests to a full pool. Use `gateway-error`.
- **Leaving out `retries` on the POST rule.** The default still retries. Use `attempts: 0`.
- **A read timeout of 2s.** It is shorter than `(2 + 1) × 1s`, so the proxy cuts off the retries and the client gets a `504`.
- **`maxEjectionPercent` at the default.** 10% of three endpoints is zero, so nothing is ejected, and `localityLbSetting` has no effect either.
- **Putting the catch-all rule first.** The POST rule becomes unreachable.
- **Testing the pool one request at a time.** `-c 1` never reaches a concurrency limit, however many requests you send.
- **Scaling or deleting `ledger-bad`.** The grader checks all three replica counts.
- **Reading the `503` count alone.** One run mixes two different causes, and the `UO` flag is what separates them.
