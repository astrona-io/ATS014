# Solution Walkthrough

Astronaut, here is the mission debrief. One object with four fields pulls the damaged ship out of formation, and one of those fields is the whole exercise: its default silently makes the policy do nothing on a squadron this small.

---

## Step 1: See the Problem

```sh
kubectl -n outlier-demo get pods -o wide
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
httpbin-bad-7d8c9f45b-q2wxl    1/1   Running   10.244.0.15
httpbin-good-6f4b8d7c9-kn3pz   1/1   Running   10.244.0.14
tester-5c9d7f8b6-x4mtv         1/1   Running   10.244.0.16
NAME      ENDPOINTS                            AGE
httpbin   10.244.0.14:8080,10.244.0.15:8080    5m
200 503 200 503 503 200 200 503 200 503 200 503 200 200 503 200 503 200 503 200
```

Note `httpbin-bad` is **`1/1` Running** and listed as a Service endpoint. Kubernetes has no complaint. Write down `10.244.0.15` — that is the pod the proxy should learn to avoid.

---

## Step 2: Choose `maxEjectionPercent` Deliberately

This is the decision the task is really testing.

```text
endpoints: 2
maxEjectionPercent default = 10%   →  2 × 10% = 0.2  →  0 endpoints ejectable
```

Ten percent of two endpoints, rounded down, is **zero**. The policy would run, count the failures correctly, and never eject anything — with no error and no warning anywhere.

You need at least 50% for one of two endpoints to be removable. `100` is the right answer here: with only two endpoints and one of them permanently broken, you would rather route everything to the good one than keep half your traffic failing.

---

## Step 3: Apply the Policy

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-httpbin.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: outlier-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
EOF
kubectl apply -f destinationrule-httpbin.yaml
istioctl proxy-config cluster deploy/tester -n outlier-demo \
  --fqdn httpbin.outlier-demo.svc.cluster.local -o json | grep -A6 outlierDetection
```

```text
destinationrule.networking.istio.io/httpbin created
"outlierDetection": {
  "consecutive5xxErrors": 3,
  "interval": "5s",
  "baseEjectionTime": "30s",
  "maxEjectionPercent": 100
```

---

## Step 4: Drive Enough Traffic

Detection is passive, and it needs **three consecutive failures on the same endpoint**. Load balancing keeps handing requests to the good pod in between, so this takes more traffic than you would guess.

```sh
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
200 503 503 200 503 503 503 200 200 503 200 200 200 200 200 200 200 200 200 200 ...
```

The 503s cluster at the start and then stop. That transition is the ejection — three consecutive failures landed, the next five-second analysis sweep ran, and the endpoint was removed from this proxy's pool.

Twenty requests would often not have got there. If nothing ejects, send more before assuming the object is wrong.

---

## Step 5: Prove the Ejection

**The counters:**

```sh
kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'httpbin.*ejections_(active|total|enforced_consecutive_5xx)'
```

```text
cluster.outbound|8000||httpbin...outlier_detection.ejections_active: 1
cluster.outbound|8000||httpbin...outlier_detection.ejections_enforced_consecutive_5xx: 1
cluster.outbound|8000||httpbin...outlier_detection.ejections_total: 1
```

`enforced_consecutive_5xx` names which rule fired, which matters once several thresholds are configured.

**The endpoint view:**

```sh
istioctl proxy-config endpoints deploy/tester -n outlier-demo \
  --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"
```

```text
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.14:8080     HEALTHY     OK                outbound|8000||httpbin...
10.244.0.15:8080     HEALTHY     FAILED            outbound|8000||httpbin...
```

Read the two columns separately. `STATUS: HEALTHY` is the control plane's view; `OUTLIER CHECK: FAILED` is this proxy's own verdict on `10.244.0.15` — the bad pod you noted in step 1.

---

## Step 6: Confirm Kubernetes Still Disagrees

```sh
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo get deploy httpbin-bad
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
```

```text
NAME      ENDPOINTS                            AGE
httpbin   10.244.0.14:8080,10.244.0.15:8080    12m
NAME          READY   UP-TO-DATE   AVAILABLE
httpbin-bad   1/1     1            1
  40 200
```

Both endpoints still listed, the bad pod still ready, and forty out of forty requests now succeed. Nothing changed in Kubernetes — the change is entirely inside the `tester` proxy.

---

## Step 7: Watch It Expire

Worth doing once so you recognise the pattern rather than mistaking it for instability:

```sh
for i in 1 2 3 4 5 6; do
  kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null | grep -E 'httpbin.*ejections_(active|total)' | awk -F': ' '{printf "%s ", $2}'
  echo
  kubectl -n outlier-demo exec deploy/tester -- sh -c \
    'for i in $(seq 1 20); do curl -s -o /dev/null http://httpbin:8000/get; done'
done
```

```text
1 1
1 1
0 1
1 2
1 2
1 2
```

`active` drops to 0 when `baseEjectionTime` expires, the endpoint is retried, it fails again, and it is re-ejected — this time for twice as long. `total` only climbs. A permanently broken pod produces this cycle, not a steady state.

---

## Common Mistakes

- **Leaving `maxEjectionPercent` at its default.** 10% of two endpoints is zero. The single most common reason this task fails.
- **Testing with too few requests.** Each endpoint counts only the signals that reach it. With several pods, the broken one gets only its share of the traffic, so you need a few times `consecutive5xxErrors` requests before it has failed enough times in a row.
- **Deleting or scaling `httpbin-bad`.** The grader checks it is still running — the proxy has to be the one that stops using it.
- **Adding a retry policy.** It would hide the failures the detector needs to see, and the grader rejects it.
- **Looking at `kubectl get endpoints` for proof.** It never changes. Use the proxy's stats and `proxy-config endpoints`.
- **Checking `ejections_active` at the wrong moment.** It flickers to 0 between ejections. `ejections_total` is the monotonic one.
- **Setting `minHealthPercent` high.** At 60% on two endpoints, ejecting one would breach the floor and ejection is disabled entirely.
