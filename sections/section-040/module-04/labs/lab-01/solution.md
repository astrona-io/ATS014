# Solution Walkthrough

The answer is one `DestinationRule` with two blocks. The task looks like it is about locality, that is, which zone the client prefers. The block that really makes it work is the other one: outlier detection, which notices that the endpoint in the client's own zone is failing.

---

## Step 1: See Why This Is Broken

```sh
kubectl -n locality-demo get pods -o wide
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local" -o json \
  | grep -E '"address"|"zone"'
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
NAME                              READY   STATUS    RESTARTS   AGE   IP            NODE                                     NOMINATED NODE   READINESS GATES
httpbin-zone-a-6788dbbdd8-d2zq8   2/2     Running   0          30s   10.244.0.9    astro-ats-014-lab-040-04-control-plane   <none>           <none>
httpbin-zone-b-679bd5d96-q8v8m    2/2     Running   0          31s   10.244.0.8    astro-ats-014-lab-040-04-control-plane   <none>           <none>
tester-69699fd775-7p784           2/2     Running   0          30s   10.244.0.10   astro-ats-014-lab-040-04-control-plane   <none>           <none>
                "address": {
                        "address": "10.244.0.9",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.8",
                    "zone": "zone-b"
200 200 200 200 503 503 200 503 200 200 503 200 503 503 200 200 200 503 200 503
```

About half the requests fail. Both endpoints are healthy as far as Kubernetes is concerned, and both have a locality. With no `DestinationRule` there is no locality preference at all, because Istio only applies it to a host that has `outlierDetection`. So the proxy of `tester` spreads the requests over both endpoints, and every request that goes to `zone-a` gets a `503`.

Nothing in the mesh knows that `zone-a` is broken. That is the gap to close.

---

## Step 2: Work Out What Is Actually Missing

The first idea is often the `failover` field. It would not help.

```text
"fail over when the locality has no HEALTHY endpoints"
                                      │
                                      └─ who decides "healthy"?
                                             │
                                  outlierDetection — and nothing else
```

The `zone-a` endpoint returns 503 while it stays ready. Without outlier detection, every measure Istio has says it is healthy. So there is nothing to fail over *from*.

So the object needs **both** blocks: `outlierDetection` to mark the endpoint unhealthy, and `localityLbSetting` to switch the locality preference on.

You also need to choose `maxEjectionPercent`, the largest share of endpoints the proxy may eject at the same time. 10% of two endpoints is zero, so with the default the proxy would count the failures and eject nothing.

---

## Step 3: Apply Both Halves

Write the manifest to a file and apply the file. On the exam this habit pays off: you can read the file again, edit it and apply it again.

Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: locality-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
    loadBalancer:
      localityLbSetting:
        enabled: true
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

Then check the result:

```sh
istioctl proxy-config cluster deploy/tester -n locality-demo \
  --fqdn httpbin.locality-demo.svc.cluster.local -o json | grep -A6 outlierDetection
```

```text
destinationrule.networking.istio.io/httpbin created
"outlierDetection": {
  "consecutive5xxErrors": 2,
  "interval": "5s",
  "baseEjectionTime": "30s",
  "maxEjectionPercent": 100
```

Note that both keys sit under the same `trafficPolicy`: `outlierDetection` and `loadBalancer` are at the same level.

---

## Step 4: Drive Traffic

Outlier detection is passive: the proxy only learns from real requests. It needs two failures in a row on `zone-a`. With `outlierDetection` in place, the locality preference now sends the requests of `tester` to `zone-a` first, so those failures arrive quickly.

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
503 503 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 ...
```

Two requests fail, then the proxy ejects the endpoint and every later request succeeds. The change is sudden because the locality preference sends the first requests straight to the broken endpoint in the client's zone, so the two failures needed for an ejection arrive at once.

---

## Step 5: Prove the Ejection and the Move

```sh
kubectl -n locality-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'httpbin.*ejections_(active|total)'
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local"
```

```text
cluster.outbound|8000||httpbin...outlier_detection.ejections_active: 1
cluster.outbound|8000||httpbin...outlier_detection.ejections_total: 1
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.21:8080     HEALTHY     FAILED            outbound|8000||httpbin...
10.244.0.22:8080     HEALTHY     OK                outbound|8000||httpbin...
```

`10.244.0.21` is the `zone-a` pod. The `STATUS` column, which comes from Kubernetes readiness, still says `HEALTHY`. The `OUTLIER CHECK` column says `FAILED`: this proxy has ejected the endpoint.

Now confirm where traffic is going:

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
kubectl -n locality-demo logs deploy/tester -c istio-proxy --tail=40 \
  | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
  40 200
  40 10.244.0.22:8080
```

All 40 requests succeeded, and `zone-b` served all of them. The traffic left the client's own locality because the proxy judged the endpoint there unhealthy. That is the failover path, not endpoint removal.

---

## Step 6: Confirm Nothing Was Removed

```sh
kubectl -n locality-demo get deploy
kubectl -n locality-demo get endpoints httpbin
```

```text
NAME             READY   UP-TO-DATE   AVAILABLE
httpbin-zone-a   1/1     1            1
httpbin-zone-b   1/1     1            1
NAME      ENDPOINTS                            AGE
httpbin   10.244.0.21:8080,10.244.0.22:8080    14m
```

Both Deployments still run, and both pods are still Service endpoints. Nothing in Kubernetes changed.

---

## Try Removing the Other Half

Try this once, because it shows why outlier detection is required:

```sh
kubectl -n locality-demo patch destinationrule httpbin --type json \
  -p '[{"op":"remove","path":"/spec/trafficPolicy/outlierDetection"}]'
sleep 40
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503
```

`localityLbSetting` is still there, unchanged and valid, yet every request fails again. Apply the full object again before you submit.

---

## Common Mistakes

- **`localityLbSetting` with no `outlierDetection`.** The main mistake. Locality load balancing has no health checker of its own.
- **`maxEjectionPercent` left at 10%.** With two endpoints, the proxy may eject none of them, so nothing ever happens.
- **Using `failover`.** It works between regions, and there is one region here. With `outlierDetection` in place, the locality preference already moves requests between zones.
- **Scaling `httpbin-zone-a` to zero.** That is endpoint removal, and it works without outlier detection. It proves nothing, and the grader checks the replica count.
- **Not checking localities first.** An endpoint with an empty locality makes every setting here a no-op, with no error.
- **Testing with too few requests.** Passive detection needs the failures to happen first.
- **Checking `ejections_active` at the wrong moment.** It drops to 0 when the ejection expires, before the endpoint fails again. `ejections_total` only climbs.
