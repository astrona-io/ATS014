# Solution Walkthrough

The `probe` Service has no protection at all. One `DestinationRule` adds both halves of a circuit breaker: a small connection pool and outlier detection. The walkthrough grows one file in three steps. Items 1 and 2 write the connection pool. Item 3 adds outlier detection, and item 4 shows why a third field, `maxEjectionPercent`, decides whether an ejection really happens. Items 5 to 7 prove the result.

---

## Start: Confirm The Starting State

The task describes three `probe` pods behind one Service, and no `DestinationRule`. One pod, `probe-broken`, answers every request with `503`. Check the pods, the Istio objects and the Deployments, and send 15 single requests from the `shuttle` pod:

```sh
kubectl -n starfleet get pods -L app,version | grep -E "NAME|probe|shuttle|fortio"
kubectl -n starfleet get destinationrule
for i in $(seq 1 15); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl -n starfleet get endpointslices -l kubernetes.io/service-name=probe
```

```text
NAME                            READY   STATUS    RESTARTS   AGE   APP       VERSION
fortio-6bbf487db8-pxjsb         2/2     Running   0          27s   fortio    
probe-broken-5d7dc9b96f-pcbfb   2/2     Running   0          6s    probe     broken
probe-v1-7888d6c6d5-9f7rt       2/2     Running   0          27s   probe     v1
probe-v2-58767cc46-fkmwf        2/2     Running   0          27s   probe     v2
shuttle-66b57f7c-s9qsh          2/2     Running   0          27s   shuttle   
No resources found in starfleet namespace.
  11 200
   4 503
NAME           REPLICAS   UID
fortio         1          5b1494ce-1e74-4b0f-b5ec-5907a17b4665
probe-broken   1          08e10ad2-1058-4c08-8c45-99903d944c99
probe-v1       1          37346db0-0ddd-438e-af76-7204884c8071
probe-v2       1          a078fd55-2748-42fb-a85d-60f2ab22942b
shuttle        1          6cf4b665-e83f-406f-bc06-b48686f1c480
{"app":"probe"} 8000
NAME          ADDRESSTYPE   PORTS   ENDPOINTS                           AGE
probe-tn82p   IPv4          8080    10.244.0.7,10.244.0.6,10.244.0.10   28s
```

About one request in three reaches the broken pod and fails. The EndpointSlice is the Kubernetes object that lists the pod addresses behind a Service. It lists all three pods, including the broken one. Item 7 compares against these outputs.

---

## Items 1 And 2: One `DestinationRule` With A Connection Pool

> **Task item 1:** There is **exactly one** `DestinationRule` for the `probe` host in `starfleet`, and it holds both a `connectionPool` and an `outlierDetection`.
>
> **Task item 2:** The connection pool allows at most **1** TCP connection (`maxConnections: 1`) and at most **1** waiting HTTP request (`http1MaxPendingRequests: 1`).

A `DestinationRule` is the Istio object that holds policies for traffic to one host. The connection pool limits how many connections and waiting requests the sidecar proxy of a client may have open to the host. A sidecar proxy is the Envoy container that Istio adds to each pod. Keep both halves in one object, because two objects for one host do not combine reliably. Start with the connection pool. `maxConnections` belongs under `tcp`, and the two `http` settings belong under `http`. Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
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
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe created
```

Check item 2. Print the connection pool, and list the `DestinationRule` objects:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy.connectionPool}{"\n"}'
kubectl -n starfleet get destinationrule -o name
```

```text
{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}}
destinationrule.networking.istio.io/probe
```

The pool allows 1 connection and 1 waiting request, and there is one `DestinationRule`. The `outlierDetection` part of item 1 follows in item 3.

---

## Item 3: Add Outlier Detection

> **Task item 3:** Outlier detection marks an endpoint as failing after **3** 5xx responses in a row (`consecutive5xxErrors`), checks every **5s** (`interval`), and ejects for a base time of **30s** (`baseEjectionTime`).

Outlier detection means that the proxy of the client removes an endpoint from its load balancing pool for a while after the endpoint fails too often in a row. Add it next to the connection pool, under the same `trafficPolicy`. Edit `destinationrule-probe.yaml`. For now, leave out `maxEjectionPercent`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

Outlier detection is passive: the proxy learns only from real responses. Send 60 single requests, in two rounds of 30. Then ask the proxy of `shuttle` for the health of the endpoints. `OUTLIER CHECK` is the verdict of this proxy about each endpoint:

```sh
for r in 1 2; do
  for i in $(seq 1 30); do
    kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
  done | sort | uniq -c
done
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
```

```text
  20 200
  10 503
  17 200
  13 503
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.6:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.7:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
```

23 of 60 requests failed, and all three endpoints show `OUTLIER CHECK: OK`. Nothing was ejected, and no error or warning tells you so. The values of item 3 are in the object, but the rule still does nothing. Item 4 explains why.

---

## Item 4: Make An Ejection Really Happen

> **Task item 4:** With these three pods, an ejection really happens: the `shuttle` proxy ejects the broken pod.

`maxEjectionPercent` is the largest share of the pool that the proxy may eject at the same time. Its default is 10%. With three endpoints, ejecting one is about 33% of the pool. That is more than 10%, so with the default the rule counts the failures but never ejects. The value `50` allows one endpoint of three to be ejected. Add the field to `destinationrule-probe.yaml`:

```yaml
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

Apply the whole file again:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

Print the final policy. Then send two rounds of 30 single requests, and read the endpoint table, the address of the broken pod, and the ejection counters of the `shuttle` proxy:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
for r in 1 2; do
  for i in $(seq 1 30); do
    kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
  done | sort | uniq -c
done
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
kubectl -n starfleet get pods -l app=probe,version=broken -o wide | awk '{print $1,$6}'
kubectl -n starfleet exec deploy/shuttle -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total):'
```

```text
{"connectionPool":{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}},"outlierDetection":{"baseEjectionTime":"30s","consecutive5xxErrors":3,"interval":"5s","maxEjectionPercent":50}}
  27 200
   3 503
  30 200
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     FAILED            outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.6:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.7:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
NAME IP
probe-broken-5d7dc9b96f-pcbfb 10.244.0.10
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_active: 1
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_total: 1
```

The object now holds both parts, which is item 1. In the first round, three `503` responses came in a row from the broken pod. Then the proxy ejected it, and the second round had no errors. The endpoint `10.244.0.10` is the broken pod. It shows `OUTLIER CHECK: FAILED`, and the counter `ejections_active` is `1`. If no endpoint shows `FAILED`, send more requests and check again. The ejection ends after `baseEjectionTime`.

---

## Item 5: `fortio` Is Refused As Overflow

> **Task item 5:** When `fortio` sends 40 requests over 4 parallel connections, its proxy refuses some of them as overflow (`upstream_rq_pending_overflow` above 0).

`fortio` is a load generator. Its flag `-c 4` sets 4 requests at the same time, and `-n 40` sets 40 requests in total. Send the load, and read the overflow counter of the `fortio` proxy:

```sh
kubectl -n starfleet exec deploy/fortio -c fortio -- \
  fortio load -c 4 -qps 0 -n 40 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"
kubectl -n starfleet exec deploy/fortio -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*upstream_rq_pending_overflow:'
```

```text
Code 200 : 12 (30.0 %)
Code 503 : 28 (70.0 %)
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_overflow: 25
```

The counter `upstream_rq_pending_overflow` is `25`, so the connection pool refused 25 requests at once. These refusals carry the response flag `UO`, which means "upstream overflow". Most of the `503` responses in this test come from the connection pool, and not from the broken pod.

---

## Item 6: Single Requests Succeed While The Pod Is Ejected

> **Task item 6:** While the broken pod is ejected, at most 1 of 10 single requests from the `shuttle` fails.

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
```

```text
  10 200
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     FAILED            outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.6:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.7:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
```

All 10 requests returned `200`, and the broken pod is still ejected. Single requests never trip the connection pool, because the limit applies to requests at the same time.

---

## Item 7: Nothing Else Changed

> **Task item 7:** The five Deployments, their labels and the `probe` Service stay unchanged. Do not add or remove workloads. The `shuttle` proxy must remove the broken pod on its own, so Kubernetes must still list it as an endpoint of the `probe` Service.

Run the Deployment, Service and EndpointSlice commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl -n starfleet get endpointslices -l kubernetes.io/service-name=probe
```

```text
NAME           REPLICAS   UID
fortio         1          5b1494ce-1e74-4b0f-b5ec-5907a17b4665
probe-broken   1          08e10ad2-1058-4c08-8c45-99903d944c99
probe-v1       1          37346db0-0ddd-438e-af76-7204884c8071
probe-v2       1          a078fd55-2748-42fb-a85d-60f2ab22942b
shuttle        1          6cf4b665-e83f-406f-bc06-b48686f1c480
{"app":"probe"} 8000
NAME          ADDRESSTYPE   PORTS   ENDPOINTS                           AGE
probe-tn82p   IPv4          8080    10.244.0.7,10.244.0.6,10.244.0.10   64s
```

The same five Deployments exist with the same `UID` values. The EndpointSlice still lists the broken pod `10.244.0.10`. Kubernetes did not change. The ejection lives only in the proxy of `shuttle`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-03/labs/lab-02
```

The grader sends live requests from `fortio` and from `shuttle`, and reads both proxies.

---

## Mistakes That Fail The Grader

- **Leaving out `maxEjectionPercent` (item 4).** The rule looks right and counts the failures, but the default of 10% blocks every ejection with three endpoints. The value must be at least 34.
- **Splitting the connection pool and outlier detection over two `DestinationRule` objects (item 1).** The task wants exactly one object for the `probe` host.
- **Leaving out `http1MaxPendingRequests` (items 2 and 5).** Without a small queue, waiting requests pile up instead of being refused, and the proxy of `fortio` shows no overflow.
- **Deleting or scaling down `probe-broken` (item 7).** The requests then succeed, but Kubernetes removed the pod, and the proxy did not. The grader checks that all five Deployments exist and that the Service still lists the broken pod.
- **Checking too late after the ejection (items 4 and 6).** With `baseEjectionTime: 30s`, the broken pod comes back after about 30 seconds. If every row says `OK`, send a round of requests and check again.
