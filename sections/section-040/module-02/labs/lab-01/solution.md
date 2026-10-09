# Solution Walkthrough

One small object sets the limits. Most of the work is in the proof, because a test that looks right can prove nothing: a limit on requests at the same time never trips when you send requests one by one.

---

## Step 1: Establish the baseline without limits

Check that no `DestinationRule` exists, then send 50 requests, 5 at a time:

```sh
kubectl -n circuit-demo get destinationrule
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
No resources found in circuit-demo namespace.
Code 200 : 50 (100.0 %)
```

All 50 requests got a `200`. Nothing limits how many requests may be open at the same time.

---

## Step 2: Apply the connection pool

Write the manifest to a file and apply the file. You can then read it again, change it and apply it again, which a command typed once does not allow.

Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: circuit-demo
spec:
  host: notification-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
```

Apply it:

```sh
kubectl apply -f destinationrule-notification-service.yaml
```

```text
destinationrule.networking.istio.io/notification-service created
```

Note the two levels under `connectionPool`. `tcp` and `http` are separate groups: `maxConnections` belongs to `tcp`, and the other two settings belong to `http`. If you put `maxConnections` under `http`, the API server rejects the object with a schema error, so you see the mistake at once.

Do **not** add a `VirtualService`. A retry policy would send the refused requests again and hide the behaviour you must show. The grader checks that none exists.

---

## Step 3: Confirm that the limits reached the proxy

`istiod`, the Istio control plane, turns the connection pool into circuit-breaker thresholds on the Envoy cluster for `notification-service`. Read them from the `fortio` sidecar proxy:

```sh
istioctl proxy-config cluster deploy/fortio -n circuit-demo \
  --fqdn notification-service.circuit-demo.svc.cluster.local -o json | grep -A8 circuitBreakers
```

```text
"circuitBreakers": {
  "thresholds": [
    {
      "maxConnections": 1,
      "maxPendingRequests": 1,
      "maxRequests": 4294967295,
      "maxRetries": 4294967295
```

You see your two settings, plus two unset fields at `2^32 - 1`, which means no limit. `maxRequests` is where `http2MaxRequests` would land. It does not bind on HTTP/1 traffic, so the HTTP/1 circuit breaker is built from the first two settings.

---

## Step 4: Prove that the limit is on requests at the same time

This step shows that you understand the limit. Send requests one at a time first:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 20 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 20 (100.0 %)
```

Twenty requests went through a pool of one connection, and all of them got a `200`. At `-c 1` there was never more than one request open, so a thousand requests would also succeed. If you stopped here, you would wrongly decide that the policy did nothing.

Now send requests 5 at a time:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 31 (62.0 %)
Code 503 : 19 (38.0 %)
```

Your split will be different. On a fast local cluster, requests finish quickly enough that many still get through. The run took about as long as the successful one, because the proxy refuses a request at once instead of delaying it.

---

## Step 5: Prove that the 503s come from the circuit breaker

Two pieces of evidence and one absence prove it.

The first is the **`UO` flag** in the access log of the client proxy:

```sh
kubectl -n circuit-demo logs deploy/fortio -c istio-proxy --tail=50 | grep ' 503 UO ' | head -2
```

```text
[2026-09-27T11:41:09.882Z] "GET /notify HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} - "-" 0 81 0 - ...
```

`UO` means upstream overflow: the proxy refused the request because a connection pool limit was full. A `503` from an application has no flag.

The second is the **overflow counter** in the client proxy:

```sh
kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats | grep notification-service | grep -E 'pending_overflow|cx_overflow'
```

The output below is shortened:

```text
cluster.outbound|80||notification-service...upstream_cx_overflow: 6
cluster.outbound|80||notification-service...upstream_rq_pending_overflow: 19
```

The proxy refused 19 requests because no waiting slot was free. `upstream_rq_pending_overflow` is the counter to name if someone asks how to prove that a circuit breaker tripped. The `fortio` pod has the `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"` annotation; without it, the proxy does not keep these counters.

The absence is in the **backend**:

```sh
kubectl -n circuit-demo logs -l app=notification-service -c istio-proxy --tail=100 | grep -c ' 503 '
```

```text
0
```

The backend's proxy logged no `503` at all. The backend never received any of the refused requests, because the client proxy refused them before they left the `fortio` pod. This difference between the two logs is the strongest single proof of where the limit acts.

---

## Common Mistakes

- **Testing with `-c 1`.** Requests sent one by one never trip a limit on requests at the same time, however many you send.
- **Adding a `VirtualService` with retries.** The retries send refused requests again, so the failure rate looks better while the real load goes up. The grader rejects it.
- **Putting `maxConnections` under `http`.** It belongs under `tcp`.
- **Looking for the `503`s in the backend's logs.** The client proxy refused them, so they are not there.
- **Deciding there is no circuit breaker because the counters are zero.** If `pending_overflow` and `cx_overflow` both stay flat while you see `503`s, the cause is somewhere else. That is useful information, not a failed test.
- **Expecting the client's limit to protect the service on its own.** Each client proxy enforces its own pool, so more clients means more open connections in total. The sidecar proxy in each backend pod also applies the same limits to what that pod accepts.
- **Forgetting `http2MaxRequests` for gRPC.** On HTTP/2, one connection carries many requests, so `maxConnections` barely limits anything.
