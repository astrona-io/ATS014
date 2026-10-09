# Solution Walkthrough

The `probe` Service had no protection at all. One `DestinationRule` with a small connection pool and outlier detection adds both, as long as `maxEjectionPercent` allows one endpoint of three to be ejected.

## Step 1: Confirm the starting state

Send 15 single requests from the `shuttle` pod, count the status codes, and look for a `DestinationRule`:

```sh
for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c
kubectl get destinationrule -n starfleet
```

```text
  11 200
   4 503
No resources found in starfleet namespace.
```

About one request in three reaches the broken pod and fails, and no `DestinationRule` exists yet.

## Step 2: Write both halves in one rule

The **connection pool** (`connectionPool`) limits how many connections and waiting requests the client's sidecar proxy may have open to the `probe`. **Outlier detection** (`outlierDetection`) makes the client's proxy eject an endpoint, that is, remove it from its load-balancing pool for a while, after it fails too often in a row. Both go under the same `trafficPolicy`. Keep them in one rule, because two rules for one host do not combine reliably.

The value that matters most is `maxEjectionPercent`, the largest share of the pool that may be ejected at the same time. Its default is 10%. With three endpoints, one ejection is 33% of the pool, so with the default nothing is ever ejected. The value `50` allows one endpoint of three to be ejected.

Save this as `destinationrule-probe.yaml`:

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
      maxEjectionPercent: 50
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe created
```

## Step 3: Prove that both halves work

Start with the connection pool. Send 30 requests over 3 parallel connections from `fortio`, then read the overflow counter of the `fortio` proxy:

```sh
kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"
kubectl exec -n starfleet deploy/fortio -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*upstream_rq_pending_overflow:'
```

```text
Code 200 : 9 (30.0 %)
Code 503 : 21 (70.0 %)
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.upstream_rq_pending_overflow: 19
```

`upstream_rq_pending_overflow: 19` counts the requests that the connection pool refused at once, with `503` and the response flag `UO` (upstream overflow). Most of the `503` responses here come from the connection pool, not from the broken pod.

Next, outlier detection. Send two rounds of 15 single requests from the `shuttle` pod:

```sh
for r in 1 2; do
  for i in $(seq 1 15); do
    kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
  done | sort | uniq -c
done
```

```text
  12 200
   3 503
  15 200
```

Three `503` responses in a row came from the broken pod, then the second round had no errors. Now read the `shuttle` proxy's endpoint list, the address of the broken pod to compare with, and the proxy's ejection counters:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
kubectl get pods -n starfleet -l app=probe,version=broken -o wide
kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total):'
```

You should see (the pod list is shortened to the name and IP columns):

```text
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     FAILED            outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.6:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
10.244.0.7:8080      HEALTHY     OK                outbound|8000||probe.starfleet.svc.cluster.local
NAME                            IP
probe-broken-5d7dc9b96f-bfjlf   10.244.0.10
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_active: 1
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_total: 1
```

The broken pod, `10.244.0.10`, has `OUTLIER CHECK: FAILED` in the `shuttle` proxy's list. Kubernetes still lists it as an endpoint of the Service:

```sh
kubectl get endpointslices -n starfleet -l kubernetes.io/service-name=probe
```

```text
NAME          ADDRESSTYPE   PORTS   ENDPOINTS                           AGE
probe-56wg5   IPv4          8080    10.244.0.6,10.244.0.7,10.244.0.10   68s
```

Now submit:

```sh
astrona submit -c sections/section-040/module-03/labs/lab-02
```

## Common mistakes

- **Leaving out `maxEjectionPercent`.** The rule looks right and counts the failures, but the 10% default blocks every ejection with three endpoints. The grader says: `outlierDetection.maxEjectionPercent is 'unset (10%)'. With three probe ships, one ejection is 33% of the list, so the limit must be at least 34 or nothing is ever ejected`.
- **Splitting the connection pool and outlier detection over two `DestinationRule` objects.** The grader wants exactly one rule for the `probe` host.
- **Leaving out `http1MaxPendingRequests`.** Without a small queue, waiting requests pile up instead of being refused, and the `fortio` proxy shows no overflow.
- **Deleting or scaling down `probe-broken`.** The requests then succeed, but Kubernetes removed the pod, not the proxy. The grader checks that all five Deployments still exist and that the Service still lists the broken pod.
- **Checking too soon after the ejection time.** With `baseEjectionTime: 30s`, the broken pod comes back after about 30 seconds. If every row says `OK`, send a round of requests and check again.
