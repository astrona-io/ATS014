# Solution Walkthrough

The solution has two objects and four features. In three places, one setting works only if another setting is right too. The walkthrough builds the `VirtualService` first (items 1 and 2), then the `DestinationRule` (items 3 to 5), and then checks each feature on its own (items 6 to 11).

---

## Start: See The Starting State

The task describes a ledger service with one broken replica, and no `VirtualService` and no `DestinationRule`. Look at the pods, the Istio objects, and the failure rate. `fortio` is a load generator. Its flag `-c 1` sets one request at a time, and `-n 30` sets 30 requests in total:

```sh
kubectl -n payments get pods -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n payments get virtualservice,destinationrule
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 30 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
kubectl -n payments get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n payments get svc ledger -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME READY STATUS IP
fortio-7d656bc7dc-m5slt 2/2 Running 10.244.0.11
ledger-bad-56d858c89-nfn9v 2/2 Running 10.244.0.8
ledger-good-67747dd96f-dm2cd 2/2 Running 10.244.0.10
ledger-good-67747dd96f-f6dsf 2/2 Running 10.244.0.9
No resources found in payments namespace.
Code 200 : 18 (60.0 %)
Code 503 : 12 (40.0 %)
NAME          REPLICAS   UID
fortio        1          153fd943-7790-4a37-ae18-173d685c21b1
ledger-bad    1          bac01d10-800e-40c4-a034-cc04523522ec
ledger-good   2          280adc9f-298a-4ac0-9652-4ac735ec119f
{"app":"ledger"} 8000
```

There are three endpoints, and one of them is broken. All pods are `Running`, so Kubernetes reports no problem. Many requests fail. Item 11 compares against the replica counts and the `UID` values above.

---

## Item 1: The Write Path

> **Task item 1:** **First**, a rule that matches the method **`POST`**: it routes to `ledger` port 8000, has a `timeout` of **`3s`**, and has retries **explicitly disabled**. A retried payment is a duplicate payment, and leaving out the `retries` block is not the same as disabling retries.

A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and retries. The sidecar proxy reads the rules from top to bottom and uses the first one that matches. The sidecar proxy is the Envoy container that Istio adds to each pod. The `POST` rule must come first, because a rule without a `match` matches everything. Write `retries` with `attempts: 0`. Without the block, Istio still retries connection failures by default, and for a payment a retry is a duplicate.

For now, add a plain second rule, so that other requests still have a route. Save this as `virtualservice-ledger.yaml`:

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
```

Apply it:

```sh
kubectl apply -f virtualservice-ledger.yaml
```

```text
virtualservice.networking.istio.io/ledger created
```

Check item 1. Print the first rule:

```sh
kubectl -n payments get virtualservice ledger -o jsonpath='{.spec.http[0]}{"\n"}'
```

```text
{"match":[{"method":{"exact":"POST"}}],"retries":{"attempts":0},"route":[{"destination":{"host":"ledger","port":{"number":8000}}}],"timeout":"3s"}
```

The rule matches `POST`, routes to `ledger` on port 8000, has `timeout` `3s`, and has `retries` with `attempts: 0`.

---

## Item 2: The Read Path

> **Task item 2:** **Second**, the catch-all rule for reads: it routes to `ledger` port 8000, has `retries` with `attempts` **2**, `perTryTimeout` **`1s`** and `retryOn` **`gateway-error`**, and a `timeout` that is long enough for all the retries to run. Calculate this time budget; do not guess it.

Do the arithmetic before you write anything:

```text
attempts: 2   ->  2 retries + 1 original try  =  3 tries
3 tries x 1s perTryTimeout                    =  3s minimum
plus headroom for connection setup            ->  timeout: 4s
```

A timeout of `2s` would cut off the retries. Use `retryOn: gateway-error` and not `5xx`. The next items add a connection pool. The proxy answers a pool rejection with a `503`. With `5xx`, the proxy would retry those rejections and add more concurrent requests to a pool that is already full. Replace the second rule in `virtualservice-ledger.yaml`:

```yaml
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

Apply the file again:

```sh
kubectl apply -f virtualservice-ledger.yaml
```

```text
virtualservice.networking.istio.io/ledger configured
```

Check item 2. Print the second rule, and print the `match` of all rules:

```sh
kubectl -n payments get virtualservice ledger -o jsonpath='{.spec.http[1]}{"\n"}'
kubectl -n payments get virtualservice ledger -o jsonpath='{.spec.http[*].match}{"\n"}'
```

```text
{"retries":{"attempts":2,"perTryTimeout":"1s","retryOn":"gateway-error"},"route":[{"destination":{"host":"ledger","port":{"number":8000}}}],"timeout":"4s"}
[{"method":{"exact":"POST"}}]
```

The second rule has the retries and the timeout of `4s`. Only the first rule has a `match`, so the second rule is the catch-all.

---

## Item 3: The Connection Pool

> **Task item 3:** `connectionPool` with `tcp.maxConnections` **2** and `http.http1MaxPendingRequests` **2**.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. The connection pool limits how many connections and waiting requests the proxy of a client may have open to the host. `maxConnections` belongs under `tcp`, and `http1MaxPendingRequests` belongs under `http`. Save this as `destinationrule-ledger.yaml`:

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
```

Apply it:

```sh
kubectl apply -f destinationrule-ledger.yaml
```

```text
destinationrule.networking.istio.io/ledger created
```

Check item 3:

```sh
kubectl -n payments get destinationrule ledger -o jsonpath='{.spec.trafficPolicy.connectionPool}{"\n"}'
```

```text
{"http":{"http1MaxPendingRequests":2},"tcp":{"maxConnections":2}}
```

---

## Item 4: Outlier Detection

> **Task item 4:** `outlierDetection` with `consecutive5xxErrors` **3**, `interval` **`5s`**, `baseEjectionTime` **`30s`**, and a `maxEjectionPercent` that can really eject one endpoint out of three.

Outlier detection means that the proxy removes an endpoint from its load balancing pool for a while after the endpoint fails too often in a row. Choose `maxEjectionPercent` with care. It is the largest share of the pool that the proxy may eject at the same time. The default is 10%, and 10% of three endpoints is 0.3, which rounds down to zero. You need at least `34` to eject one endpoint. Use `100`: one of the three is really broken, and you want the proxy to avoid it completely. Add the block next to `connectionPool`. Edit `destinationrule-ledger.yaml`:

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
```

Apply it:

```sh
kubectl apply -f destinationrule-ledger.yaml
```

```text
destinationrule.networking.istio.io/ledger configured
```

Check item 4:

```sh
kubectl -n payments get destinationrule ledger -o jsonpath='{.spec.trafficPolicy.outlierDetection}{"\n"}'
```

```text
{"baseEjectionTime":"30s","consecutive5xxErrors":3,"interval":"5s","maxEjectionPercent":100}
```

---

## Item 5: The Locality Setting

> **Task item 5:** `loadBalancer.localityLbSetting` with `enabled: true`.

A locality is the region and zone that a pod runs in. With `localityLbSetting` enabled, the proxy prefers the endpoints in its own locality. The setting has an effect only because `outlierDetection` is in the same `trafficPolicy`, because the outlier detection is what marks an endpoint as unhealthy. Add the block at the same level. The final file looks like this:

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

```text
destinationrule.networking.istio.io/ledger configured
```

Check item 5. Print the load balancer settings, and let Istio check the objects:

```sh
kubectl -n payments get destinationrule ledger -o jsonpath='{.spec.trafficPolicy.loadBalancer}{"\n"}'
istioctl analyze -n payments
```

```text
{"localityLbSetting":{"enabled":true}}
Info [IST0135] (Pod payments/fortio-7d656bc7dc-m5slt) Annotation "sidecar.istio.io/statsInclusionPrefixes" has been deprecated and may not work in future Istio versions.
```

The locality setting is enabled. The analyzer prints only an information message about an annotation of the `fortio` pod. It does not matter for this task.

---

## Items 6 And 7: Reads Are Tried Three Times, Writes Once

> **Task item 6:** A `GET /status/503` reaches the service **3** times: the original request plus two retries.
>
> **Task item 7:** A `POST /status/503` reaches the service exactly **1** time.

The client gets one response however many tries happened, so the proof is on the server side. The sidecar proxy of a ledger pod writes one access log line for each request. Count the lines for `/status/503` before and after one request of each method. Wait before each count, because the proxy writes the line a moment after the request:

```sh
for method in GET POST; do
  sleep 5
  BEFORE=$(kubectl -n payments logs -l app=ledger -c istio-proxy --tail=-1 | grep -c /status/503)
  kubectl -n payments exec deploy/fortio -c fortio -- \
    fortio curl -quiet -X "$method" http://ledger:8000/status/503 >/dev/null 2>&1
  sleep 5
  AFTER=$(kubectl -n payments logs -l app=ledger -c istio-proxy --tail=-1 | grep -c /status/503)
  echo "$method attempts: $((AFTER - BEFORE))"
done
```

```text
GET attempts: 3
POST attempts: 1
```

The path and the status are the same. Only the method differs. The `GET` request reached the service three times, and the `POST` request once, because the method match sent the two requests to different rules.

---

## Item 8: The Read Timeout Is Long Enough

> **Task item 8:** The `timeout` of the read rule is at least `(attempts + 1) × perTryTimeout`.

```sh
kubectl -n payments get virtualservice ledger \
  -o jsonpath='timeout={.spec.http[1].timeout} attempts={.spec.http[1].retries.attempts} perTry={.spec.http[1].retries.perTryTimeout}{"\n"}'
```

```text
timeout=4s attempts=2 perTry=1s
```

The formula gives `(2 + 1) × 1s = 3s`, and the timeout is `4s`.

---

## Item 9: The Pool Refuses Concurrent Requests

> **Task item 9:** A concurrent `fortio` run produces `503` responses with the **`UO`** response flag (upstream overflow), and the `upstream_rq_pending_overflow` counter increases.

Send 80 requests, 8 at a time. Read the overflow counter of the `fortio` proxy before and after, and count the `503 UO` lines in its access log:

```sh
BEFORE=$(kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep 'ledger.*pending_overflow' | awk -F': ' '{print $2}')
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 8 -qps 0 -n 80 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
AFTER=$(kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep 'ledger.*pending_overflow' | awk -F': ' '{print $2}')
echo "pending_overflow +$((AFTER - BEFORE))"
sleep 2
kubectl -n payments logs deploy/fortio -c istio-proxy --tail=150 | grep -c ' 503 UO '
```

```text
Code 200 : 74 (92.5 %)
Code 503 : 6 (7.5 %)
pending_overflow +6
6
```

The pool refused 6 requests, and the counter rose by 6. The log has 6 lines with `503 UO`. `UO` means "upstream overflow": the proxy refused the request because a limit of the connection pool was full. A `503` from the broken replica has no such flag, so the flag separates the two causes of `503`. Your numbers will differ. They depend on how many failures the proxy has already seen.

---

## Item 10: The Failing Endpoint Is Ejected

> **Task item 10:** After the grader sends traffic, the failing endpoint is ejected: `OUTLIER CHECK: FAILED`, or the ejection counters have increased.

Send 80 requests, 2 at a time, wait, and read the ejection counters and the endpoint table of the `fortio` proxy:

```sh
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 2 -qps 0 -n 80 -loglevel Warning http://ledger:8000/get >/dev/null 2>&1
sleep 6
kubectl -n payments exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep -E 'ledger.*ejections_(active|total)'
istioctl proxy-config endpoints deploy/fortio -n payments \
  --cluster "outbound|8000||ledger.payments.svc.cluster.local"
```

```text
cluster.outbound|8000||ledger.payments.svc.cluster.local;.outlier_detection.ejections_active: 1
cluster.outbound|8000||ledger.payments.svc.cluster.local;.outlier_detection.ejections_total: 1
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     OK                outbound|8000||ledger.payments.svc.cluster.local
10.244.0.8:8080      HEALTHY     FAILED            outbound|8000||ledger.payments.svc.cluster.local
10.244.0.9:8080      HEALTHY     OK                outbound|8000||ledger.payments.svc.cluster.local
```

`10.244.0.8` is `ledger-bad`. Its `STATUS` is still `HEALTHY`, because that column comes from the readiness of Kubernetes. Its `OUTLIER CHECK` is `FAILED`, because the proxy of `fortio` ejected it. Now send single requests again:

```sh
kubectl -n payments exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 40 -loglevel Warning http://ledger:8000/get 2>&1 | grep 'Code '
```

```text
Code 200 : 40 (100.0 %)
```

All 40 requests succeed. At the start, 12 of 30 failed. The retries of the read rule hid most failures from the client, but outlier detection still counted every one of them, because it looks at each try and not at the result that the client sees.

---

## Item 11: Nothing Else Changed

> **Task item 11:** All three ledger Deployments still run with their original replica counts, and the Service selector is unchanged.

```sh
kubectl -n payments get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n payments get svc ledger -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl -n payments get endpoints ledger
```

```text
NAME          REPLICAS   UID
fortio        1          153fd943-7790-4a37-ae18-173d685c21b1
ledger-bad    1          bac01d10-800e-40c4-a034-cc04523522ec
ledger-good   2          280adc9f-298a-4ac0-9652-4ac735ec119f
{"app":"ledger"} 8000
NAME     ENDPOINTS                                          AGE
ledger   10.244.0.10:8080,10.244.0.8:8080,10.244.0.9:8080   89s
```

The output is the same as before. The replica counts are 1, 1 and 2, the `UID` values are the same, and the Service still lists all three pods, including the broken one. The ejection lives only in the proxy.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/capstone/labs/lab-01
```

The grader counts the requests at the server, runs a concurrent load test, and reads the logs and the counters.

---

## Mistakes That Fail The Grader

- **`retryOn: 5xx` together with a connection pool (item 2).** Pool rejections are `503` responses, and retrying them adds more concurrent requests to a full pool. Use `gateway-error`.
- **Leaving out `retries` on the `POST` rule (item 1).** The default still retries. Use `attempts: 0`.
- **A read timeout of 2s (items 2 and 8).** It is shorter than `(2 + 1) × 1s`, so the proxy cuts off the retries and the client gets a `504`.
- **`maxEjectionPercent` at the default (items 4 and 10).** 10% of three endpoints is zero, so nothing is ejected, and `localityLbSetting` has no effect either.
- **Putting the catch-all rule first (items 1 and 2).** The `POST` rule becomes unreachable.
- **Testing the pool one request at a time (item 9).** `-c 1` never reaches a concurrency limit, however many requests you send.
- **Scaling or deleting `ledger-bad` (item 11).** The grader checks all three replica counts.
- **Reading the `503` count alone (item 9).** One run mixes two different causes, and the `UO` flag separates them.
