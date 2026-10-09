# Solution Walkthrough

One `DestinationRule` with two blocks. The task looks like it is about locality (which planet's ships you prefer), and the half that actually makes it work is the other one: noticing that the nearby ships are damaged.

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

About half the requests fail. Both endpoints are healthy as far as Kubernetes is concerned, and both carry a locality. With no `DestinationRule` there is no locality preference at all: Istio only applies it to a host that has `outlierDetection`. So the signals spread over both endpoints, and every one that lands on `zone-a` gets its `503`.

Nothing in the mesh knows that `zone-a` is broken. That is the gap to close.

---

## Step 2: Work Out What Is Actually Missing

The instinct is to reach for `failover`. It would not help.

```text
"fail over when the locality has no HEALTHY endpoints"
                                      │
                                      └─ who decides "healthy"?
                                             │
                                  outlierDetection — and nothing else
```

`zone-a`'s endpoint is returning 503 while staying ready. Without outlier detection it is, by every measure Istio has, perfectly healthy. There is nothing to fail over *from*.

So the object needs **both** blocks: one to make the endpoint unhealthy, one to make locality awareness explicit.

And `maxEjectionPercent` needs deciding: 10% of two endpoints is zero, so the default would count the failures and eject nothing.

---

## Step 3: Apply Both Halves

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

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

Note both keys sit under the same `trafficPolicy` — `outlierDetection` and `loadBalancer` are siblings.

---

## Step 4: Drive Traffic

Detection is passive. It needs two consecutive failures on `zone-a`. With `outlierDetection` in place, the locality preference now sends the tester's signals to `zone-a` first, so those failures arrive quickly.

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
503 503 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 ...
```

Two failures, then the ejection lands and everything after it succeeds. The transition is sharp because the locality preference sends the first signals straight to the nearby, broken endpoint, so the two failures needed for an ejection arrive at once.

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

`10.244.0.21` is the `zone-a` pod: still `HEALTHY` to the control plane, `FAILED` to this proxy. That column is the ejection.

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

Forty for forty, all served from `zone-b`. Traffic left the caller's own locality because the endpoint there was judged unhealthy — which is the failover path, not endpoint removal.

---

## Step 6: Confirm You Did Not Cheat

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

Both still running, both still Service endpoints. Nothing in Kubernetes changed.

---

## Try Removing the Other Half

Worth doing once, because it is the module's whole point:

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

`localityLbSetting` is still there, unchanged and valid. Every request fails again. Re-apply the full object before submitting.

---

## Common Mistakes

- **`localityLbSetting` with no `outlierDetection`.** The headline failure. Locality has no health checker of its own.
- **`maxEjectionPercent` left at 10%.** Two endpoints, zero ejectable — the two defaults compound into complete inaction.
- **Reaching for `failover`.** It is region-level and there is one region here; with `outlierDetection` in place, the locality preference already handles zone spillover.
- **Scaling `httpbin-zone-a` to zero.** That is endpoint removal and it works without outlier detection — it proves nothing, and the grader checks the replica count.
- **Not checking localities first.** An endpoint with an empty locality makes every setting here a no-op, with no error.
- **Testing with too few requests.** Passive detection needs the failures to arrive first.
- **Checking `ejections_active` at the wrong moment.** It drops to 0 when the ejection expires, before the endpoint fails again. `ejections_total` only climbs.
