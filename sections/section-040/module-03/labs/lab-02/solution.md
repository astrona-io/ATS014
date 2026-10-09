# Solution Walkthrough

Mission debrief, astronaut. The probe had no shields at all. One `DestinationRule` with a small connection pool and outlier detection raises both, as long as the ejection limit lets one ship of three be removed.

---

## Step 1: Confirm the starting state

Send 15 single signals from the shuttle, and look for a `DestinationRule`:

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

About one signal in three lands on the broken ship and fails, and nothing protects the probe yet.

## Step 2: Raise both shields in one rule

Both halves live under the same `trafficPolicy`. Keep them in one rule: two rules for one host do not combine reliably.

The value that matters most is `maxEjectionPercent`. Its default is 10%, and with three ships one ejection is 33% of the list, so with the default nothing is ever ejected. `50` lets one ship of three out.

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

## Step 3: Prove both halves work

**The connection pool.** Fire 30 signals over 3 parallel connections from fortio, then read fortio's overflow counter:

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

`upstream_rq_pending_overflow: 19` counts the signals the pool refused at once, with `503 UO`. Most of the `503`s here are the shield doing its job, not the broken ship.

**Outlier detection.** Send two rounds of 15 single signals from the shuttle:

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

Three `503`s in a row from the broken ship, then a clean round. Now read the shuttle's own verdict, and the broken ship's IP to compare with:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
kubectl get pods -n starfleet -l app=probe,version=broken -o wide
kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total):'
```

You should see (the pod list trimmed to the name and IP columns):

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

The broken ship, `10.244.0.10`, is `FAILED` in the shuttle's view. Kubernetes still lists it:

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

---

## Common Mistakes

- **Leaving out `maxEjectionPercent`.** The rule looks right and counts the failures, but the 10% default blocks every ejection on three ships. The grader says: `outlierDetection.maxEjectionPercent is 'unset (10%)'. With three probe ships, one ejection is 33% of the list, so the limit must be at least 34 or nothing is ever ejected`.
- **Splitting the shields over two `DestinationRule`s.** The grader wants exactly one rule for the probe host.
- **Leaving out `http1MaxPendingRequests`.** Without a small queue, waiting signals pile up instead of being refused, and fortio's proxy shows no overflow.
- **Deleting or scaling down `probe-broken`.** The signals succeed, but that is Kubernetes removing the ship, not the proxy. The grader checks that all five Deployments are still there and that the Service still lists the broken ship.
- **Checking too soon after the ejection time.** With `baseEjectionTime: 30s` the broken ship comes back after about 30 seconds. If every row says `OK`, send a round of signals and look again.
