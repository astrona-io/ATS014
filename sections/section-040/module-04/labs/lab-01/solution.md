# Solution Walkthrough

One [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) with two blocks. The task looks like it is about locality, and the half that actually makes it work is the other one.

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
httpbin-zone-a-...   1/1   Running   10.244.0.21
httpbin-zone-b-...   1/1   Running   10.244.0.22
tester-...           1/1   Running   10.244.0.23
"address": "10.244.0.21",
"zone": "zone-a",
"address": "10.244.0.22",
"zone": "zone-b",
503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503 503
```

Every request fails. Both endpoints are healthy as far as Kubernetes is concerned, both carry a locality — and Istio's **default preference** is sending everything to `zone-a`, the caller's own locality, which happens to be the broken one.

That is worth sitting with: the default that normally saves you latency and money is, here, routing 100% of traffic into a failing endpoint. Preference alone has no notion of health.

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

And `maxEjectionPercent` needs deciding, for module 3's reason: 10% of two endpoints is zero, so the default would count the failures and eject nothing.

---

## Step 3: Apply Both Halves

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-httpbin.yaml <<'EOF'
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
EOF
kubectl apply -f destinationrule-httpbin.yaml
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

Detection is passive. It needs two consecutive failures on `zone-a`, which — since preference is sending it nearly everything — arrive quickly here.

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
503 503 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 ...
```

Two failures, then the ejection lands and everything after it succeeds. The transition is much sharper than in module 3 because locality preference was concentrating traffic on the bad endpoint rather than diluting it — the thing that made the problem worse makes the detection faster.

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
- **Reaching for `failover`.** It is region-level and there is one region here; the default preference already handles zone spillover.
- **Scaling `httpbin-zone-a` to zero.** That is endpoint removal and it works without outlier detection — it proves nothing, and the grader checks the replica count.
- **Not checking localities first.** An endpoint with an empty locality makes every setting here a no-op, with no error.
- **Testing with too few requests.** Passive detection needs the failures to arrive first.
- **Checking `ejections_active` at the wrong moment.** It drops to 0 when the ejection expires, before the endpoint fails again. `ejections_total` only climbs.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [OutlierDetection API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#OutlierDetection) — `consecutive5xxErrors`, `interval`, `baseEjectionTime`, `maxEjectionPercent`
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [LocalityLoadBalancerSetting API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LocalityLoadBalancerSetting) — `distribute`, `failover` and the health dependency
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
