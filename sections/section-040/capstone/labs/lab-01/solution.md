# Solution Walkthrough

Astronaut, this is the full mission debrief. Two objects, four features, and three places where getting one right depends on having got another right. Build the `VirtualService` first, then the `DestinationRule`, then verify each feature separately.

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

Three endpoints, one poisoned, all `1/1` Running — Kubernetes has no complaint. One request in three fails.

---

## Step 2: Do the Budget Arithmetic

Before writing the read rule:

```text
attempts: 2  →  2 retries + 1 original  =  3 attempts
3 × perTryTimeout 1s                    =  3s minimum
plus headroom                           →  timeout: 4s
```

`4s` satisfies the grader's `(attempts + 1) × perTryTimeout` check with a second to spare. `3s` would be exactly at the limit and leaves nothing for connection setup; `2s` truncates the retries.

---

## Step 3: The VirtualService — Writes First

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-ledger.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-ledger.yaml
```

Two details that fail the task if wrong:

- **`attempts: 0`, not an omitted block.** Omitting `retries` leaves Istio's implicit default of 2 attempts on connection-level failures. For a payment, that is a duplicate.
- **`retryOn: gateway-error`, not `5xx`.** This matters more here than in the module, because the next step adds a connection pool — and a pool rejection is a `503`. Under `5xx` those rejections would be retried, adding concurrent work to a pool that just told you it was full.

---

## Step 4: The DestinationRule — All Three Policies

```sh
cat > destinationrule-ledger.yaml <<'EOF'
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
EOF
kubectl apply -f destinationrule-ledger.yaml
istioctl analyze -n payments
```

```text
destinationrule.networking.istio.io/ledger created
✔ No validation issues found when analyzing namespace: payments.
```

`maxEjectionPercent` again: three endpoints at the 10% default is `0.3`, rounded down to zero. You need at least 34 for one endpoint; `100` is right here because one of three is genuinely broken and you would rather route around it entirely.

`localityLbSetting` is the cheap part — and note it only does anything *because* `outlierDetection` sits beside it.

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

Same path, same status, different method — three attempts versus one, because the method match put them on different rules.

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

Eight concurrent callers against a pool of two connections plus two pending slots. Nineteen rejections carrying `UO` — and note the 503 count is higher than that, because some of those are the poisoned replica answering. Two different causes of 503 in the same run, distinguished only by the flag.

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

`10.244.0.24` is `ledger-bad`. Still `HEALTHY` to Kubernetes, `FAILED` to this proxy.

Worth noticing: the read path's retries were hiding most of these failures from the caller the whole time — and outlier detection still saw every one of them, because it observes attempts, not caller-visible outcomes. That combination is the one genuinely free win in this section.

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

- **`retryOn: 5xx` with a connection pool.** Pool rejections are 503s; retrying them adds concurrency to a full pool. Use `gateway-error`.
- **Omitting `retries` on the POST rule.** The implicit default still retries. Use `attempts: 0`.
- **A read timeout of 2s.** Shorter than `(2 + 1) × 1s`; the retries are truncated and the caller gets a 504.
- **`maxEjectionPercent` at the default.** 10% of three endpoints is zero — nothing ejects, and `localityLbSetting` does nothing either.
- **Putting the catch-all rule first.** The POST rule becomes unreachable.
- **Testing the pool sequentially.** `-c 1` never trips a concurrency limit however many requests you send.
- **Scaling or deleting `ledger-bad`.** The grader checks all three replica counts.
- **Reading the 503 count alone.** Two different causes are mixed in one run; the `UO` flag is what separates them.
