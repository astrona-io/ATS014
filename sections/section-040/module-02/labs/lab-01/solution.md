# Solution Walkthrough

One small object sets the limits. Items 1 to 3 describe it. Most of the work is the proof in items 4 to 10, because a test that looks right can prove nothing: a limit on requests at the same time never trips when you send requests one by one.

---

## Start: Establish The Baseline Without Limits

The task says that no `DestinationRule` exists and that the number of open requests has no limit. Check that this is true, and send 50 requests, 5 at a time, from the `fortio` pod. `fortio` is a load generator. Its flag `-c 5` sets 5 requests at the same time, and `-n 50` sets 50 requests in total:

```sh
kubectl -n circuit-demo get destinationrule,virtualservice
kubectl -n circuit-demo get pods
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
kubectl -n circuit-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
```

```text
No resources found in circuit-demo namespace.
NAME                                       READY   STATUS    RESTARTS   AGE
fortio-7d656bc7dc-hvr8h                    2/2     Running   0          6s
notification-service-v1-54dd46d4b6-mnd22   2/2     Running   0          6s
Code 200 : 50 (100.0 %)
NAME                      REPLICAS   UID
fortio                    1          da3a943b-b75b-46e5-85ae-966d077c00ea
notification-service-v1   1          04e95cbc-212e-43b0-bed7-f7be47b68eab
```

All 50 requests got a `200`. Nothing limits how many requests may be open at the same time.

---

## Items 1 And 2: Create The `DestinationRule` With A Connection Pool

> **Task item 1:** Create a `DestinationRule` named `notification-service` for the host `notification-service`.
>
> **Task item 2:** In its `trafficPolicy.connectionPool`, set:
>
> * `tcp.maxConnections` to **1**
> * `http.http1MaxPendingRequests` to **1**
> * `http.maxRequestsPerConnection` to **1**

A `DestinationRule` is the Istio object that holds policies for traffic to one host. The `connectionPool` limits how many connections and waiting requests the sidecar proxy of the client may have open to that host. A sidecar proxy is the Envoy container that Istio adds to a pod. Note the two levels under `connectionPool`. `tcp` and `http` are separate groups: `maxConnections` belongs to `tcp`, and the other two settings belong to `http`. If you put `maxConnections` under `http`, the API server rejects the object.

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

---

## Item 3: No `VirtualService`

> **Task item 3:** Do **not** create a `VirtualService`. A retry policy would hide the refusals this task is about, and the grader checks that none exists in `circuit-demo`.

You created only the `DestinationRule`. A `VirtualService` with a retry policy would send the refused requests again and hide the behaviour that you must show. Check that none exists:

```sh
kubectl -n circuit-demo get virtualservice
```

```text
No resources found in circuit-demo namespace.
```

---

## Item 4: The Three Settings Are In The Object

> **Task item 4:** The three settings are present in the object with those exact values.

```sh
kubectl -n circuit-demo get destinationrule notification-service \
  -o jsonpath='{.spec.host}{"\n"}{.spec.trafficPolicy.connectionPool}{"\n"}'
```

```text
notification-service
{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}}
```

The host is `notification-service`. The pool holds `maxConnections` `1` under `tcp`, and `http1MaxPendingRequests` `1` and `maxRequestsPerConnection` `1` under `http`.

---

## Item 5: The Limits Reached The Proxy

> **Task item 5:** The `fortio` proxy's cluster configuration shows `maxConnections: 1` and `maxPendingRequests: 1`, so the limits really reached the sidecar proxy.

`istiod`, the Istio control plane, turns the connection pool into circuit-breaker thresholds on the Envoy cluster for `notification-service`. A cluster is a named destination in Envoy. Read the thresholds from the `fortio` proxy. Wait a few seconds after the apply first:

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
                }
            ]
```

You see your two settings. The two other fields are `4294967295`, which is `2^32 - 1`, and means no limit. If `maxConnections` is not `1` yet, wait a few seconds and run the command again.

---

## Item 6: A Sequential Run Still Succeeds

> **Task item 6:** A **sequential** run (`fortio load -c 1 -n 20`) still succeeds completely (at least 19 of 20 requests get a `200`). The limit is on requests at the same time, not on the number of requests, so this run must not fail.

Send 20 requests, one at a time:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 20 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 20 (100.0 %)
```

All 20 requests got a `200`. With `-c 1`, there is never more than one request open at the same time, so a thousand requests would pass too. If you stopped here, you would wrongly decide that the policy does nothing.

---

## Item 7: A Concurrent Run Gets `503`

> **Task item 7:** A **concurrent** run (`fortio load -c 5 -n 50`) gets some `503` responses.

Send 50 requests, 5 at a time:

```sh
kubectl -n circuit-demo exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning http://notification-service/notify 2>&1 | grep 'Code '
```

```text
Code 200 : 9 (18.0 %)
Code 503 : 41 (82.0 %)
```

41 of 50 requests were refused with `503`. Your split will differ, because it depends on how fast the requests finish. At the start, the same run gave 50 times `200`.

---

## Item 8: The Refusals Carry The `UO` Flag

> **Task item 8:** Those refusals carry the **`UO`** response flag in the `fortio` proxy's access log.

The access log of the proxy has one line per request. Read the lines with `503 UO`:

```sh
sleep 2
kubectl -n circuit-demo logs deploy/fortio -c istio-proxy --tail=80 | grep ' 503 UO ' | head -2
```

```text
[2026-10-20T21:04:20.396Z] "GET /notify HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} - "-" 0 81 0 - "-" "fortio.org/fortio-1.69.5" "a22a2d0f-5324-969e-aa8e-4cb1ab77da9f" "notification-service" "-" outbound|80||notification-service.circuit-demo.svc.cluster.local - 10.96.147.248:80 10.244.0.9:50112 - default
[2026-10-20T21:04:20.398Z] "GET /notify HTTP/1.1" 503 UO upstream_reset_before_response_started{overflow} - "-" 0 81 0 - "-" "fortio.org/fortio-1.69.5" "eef66679-01a8-9dd8-81b5-48429de68072" "notification-service" "-" outbound|80||notification-service.circuit-demo.svc.cluster.local - 10.96.147.248:80 10.244.0.9:50126 - default
```

`UO` means "upstream overflow": the proxy refused the request because a limit of the connection pool was full. A `503` that comes from an application has no such flag. The upstream address is `"-"`, because no pod was chosen.

---

## Item 9: The Overflow Counter Goes Up

> **Task item 9:** The `upstream_rq_pending_overflow` counter for the `notification-service` cluster goes up during the concurrent run.

The proxy keeps counters for each cluster. Read the overflow counters of the `fortio` proxy:

```sh
kubectl -n circuit-demo exec deploy/fortio -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep notification-service | grep -E 'pending_overflow|cx_overflow'
```

```text
cluster.outbound|80||notification-service.circuit-demo.svc.cluster.local;.upstream_cx_overflow: 6
cluster.outbound|80||notification-service.circuit-demo.svc.cluster.local;.upstream_rq_pending_overflow: 41
```

The counter `upstream_rq_pending_overflow` is `41`, the same number as the refused requests in item 7. It counts the requests that the proxy refused because no waiting slot was free. This is the counter to name when someone asks how to prove that a circuit breaker tripped. The `fortio` pod has the annotation `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"`. Without it, the proxy does not keep these counters.

---

## Item 10: The Backend Logged No `503`

> **Task item 10:** The backend's own proxy logged **no** `503` responses, because the refused requests never reached it.

```sh
kubectl -n circuit-demo logs -l app=notification-service -c istio-proxy --tail=-1 | grep -c ' 503 '
```

```text
0
```

The count is `0`. The backend never received the refused requests, because the proxy of `fortio` refused them before they left the pod. The difference between this log and the log of the client proxy is the strongest single proof of where the limit acts.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-01
```

The grader runs a sequential and a concurrent load test and reads the logs and the counters.

---

## Mistakes That Fail The Grader

- **Testing with `-c 1` (items 6 and 7).** Requests that you send one by one never trip a limit on requests at the same time, however many you send.
- **Adding a `VirtualService` with retries (item 3).** The retries send refused requests again, so the failure rate looks better while the real load goes up. The grader rejects it.
- **Putting `maxConnections` under `http` (item 2).** It belongs under `tcp`.
- **Looking for the `503` responses in the logs of the backend (items 8 and 10).** The proxy of the client refused them, so they are not there.
- **Deciding that there is no circuit breaker because the counters are zero (item 9).** If `pending_overflow` stays flat while you see `503`, the cause is somewhere else.
- **Expecting the limit of one client to protect the service alone.** Each client proxy enforces its own pool, so more clients mean more open connections in total.
