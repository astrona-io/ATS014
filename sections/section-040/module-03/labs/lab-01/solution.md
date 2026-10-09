# Solution Walkthrough

One `DestinationRule` with four outlier detection fields solves this task. One of those fields is the real test: its default value makes the rule do nothing on a Service with only two endpoints.

## Step 1: See the problem

First look at the pods, the Service endpoints and the error rate. The loop sends 20 requests from the `tester` pod to the `httpbin` Service and prints each status code:

```sh
kubectl -n outlier-demo get pods -o wide
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

The output below is shortened: the `NODE`, `NOMINATED NODE` and `READINESS GATES` columns are left out.

```text
NAME                            READY   STATUS    RESTARTS   AGE   IP
httpbin-bad-854489b47f-6lfws    2/2     Running   0          13s   10.244.0.8
httpbin-good-664569f479-6zh7v   2/2     Running   0          13s   10.244.0.9
tester-69699fd775-drpgh         2/2     Running   0          13s   10.244.0.10
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                         AGE
httpbin   10.244.0.8:8080,10.244.0.9:8080   13s
503 200 503 503 200 200 200 200 503 503 200 503 503 200 200 503 503 200 503 503
```

Each pod shows `2/2`: the application container and its sidecar proxy. The `Warning` line comes from Kubernetes and does not matter here. `httpbin-bad` is `Running` and listed as an endpoint of the Service, so Kubernetes sees nothing wrong. About half of the requests return `503`. Write down the address of `httpbin-bad`, here `10.244.0.8`. That is the endpoint the proxy must learn to avoid.

## Step 2: Choose `maxEjectionPercent`

This choice is what the task really tests. `maxEjectionPercent` sets the largest share of the load-balancing pool that the proxy may eject at the same time. Its default is 10%.

Before each ejection, Envoy works out what share of the pool would be ejected after it. With two endpoints, ejecting one is 50% of the pool. That is more than 10%, so with the default the rule runs, counts the failures correctly, and never ejects anything. No error or warning tells you so.

You need at least `50` for one of two endpoints to be removable, and the grader checks for at least `50`. The value `100` is a good choice here: with two endpoints and one of them always broken, you would rather send every request to the good endpoint than keep half of them failing.

## Step 3: Apply the rule

Save this as `destinationrule-httpbin.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Then check that the rule reached the `tester` proxy. `istioctl proxy-config cluster` prints the proxy's configuration for the `httpbin` Envoy cluster, which is the proxy's name for the group of `httpbin` endpoints:

```sh
istioctl proxy-config cluster deploy/tester -n outlier-demo \
  --fqdn httpbin.outlier-demo.svc.cluster.local -o json | grep -A6 outlierDetection
```

You should see:

```text
        "outlierDetection": {
            "consecutive5xx": 3,
            "interval": "5s",
            "baseEjectionTime": "30s",
            "maxEjectionPercent": 100,
            "enforcingConsecutive5xx": 100,
            "enforcingSuccessRate": 0
```

The proxy shows Envoy's own field names. `istiod` translated `consecutive5xxErrors` into `consecutive5xx`, and added `enforcingConsecutive5xx: 100`, which means every endpoint that reaches the limit is really ejected.

## Step 4: Send enough traffic

Outlier detection is passive: the proxy only learns from real responses. It needs **three failures in a row from the same endpoint**. The load balancer sends some requests to the good pod in between, so this can take more requests than you expect:

```sh
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
200 503 200 200 503 503 200 200 200 200 200 200 200 200 200 200 200 200 200 200 ...
```

The `503` responses come at the start and then stop. That change is the ejection: three failures in a row reached the limit, and the proxy removed the endpoint from its own pool at once. The output above is shortened.

With only 20 requests, the ejection often does not happen yet. If nothing is ejected, send more requests before you change the rule.

## Step 5: Prove the ejection

The grader reads the proxy's endpoint list. `pilot-agent request GET clusters` prints every endpoint with its health flags, and an ejected endpoint carries the flag `failed_outlier_check`. This command prints one line for the ejected endpoint:

```sh
kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET clusters | grep 'outbound|8000||httpbin' | grep failed_outlier_check
```

```text
2026/10/09 20:47:49 INFO GOMEMLIMIT is already set, skipping package=github.com/KimMachineGun/automemlimit/memlimit GOMEMLIMIT=1073741824
outbound|8000||httpbin.outlier-demo.svc.cluster.local::10.244.0.8:8080::health_flags::/failed_outlier_check
```

The first line is a log message from `pilot-agent` itself, and you can ignore it. The second line names the ejected endpoint, `10.244.0.8:8080`, and its health flag.

`istioctl proxy-config endpoints` shows the same result in a table:

```sh
istioctl proxy-config endpoints deploy/tester -n outlier-demo \
  --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"
```

You should see:

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8080     HEALTHY     FAILED            outbound|8000||httpbin.outlier-demo.svc.cluster.local
10.244.0.9:8080     HEALTHY     OK                outbound|8000||httpbin.outlier-demo.svc.cluster.local
```

Read the two columns separately. `STATUS: HEALTHY` is what Kubernetes reports through `istiod`. `OUTLIER CHECK: FAILED` is this proxy's own decision about `10.244.0.8`, the bad pod from step 1.

The proxy also has counters for ejections. Istio keeps them only for pods with the annotation `sidecar.istio.io/statsInclusionPrefixes`, and the `tester` pod in this lab does not have it, so this command may print nothing:

```sh
kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'httpbin.*ejections_(active|total|enforced_consecutive_5xx)'
```

On a pod that keeps the counters, for example with the annotation `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound|8000||httpbin"` on its pod template, the output looks like this (the `pilot-agent` log line is left out):

```text
cluster.outbound|8000||httpbin.outlier-demo.svc.cluster.local;.outlier_detection.ejections_active: 1
cluster.outbound|8000||httpbin.outlier-demo.svc.cluster.local;.outlier_detection.ejections_enforced_consecutive_5xx: 1
cluster.outbound|8000||httpbin.outlier-demo.svc.cluster.local;.outlier_detection.ejections_total: 1
```

`ejections_enforced_consecutive_5xx` names the rule that ejected the endpoint. That helps when several limits are set.

## Step 6: Confirm that Kubernetes did not change

Check the Service endpoints and the bad Deployment, then send 40 requests and count the status codes:

```sh
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo get deploy httpbin-bad
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
```

```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                         AGE
httpbin   10.244.0.8:8080,10.244.0.9:8080   50s
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
httpbin-bad   1/1     1            1           50s
  40 200
```

Both endpoints are still listed, the bad pod is still ready, and all 40 requests succeed. Nothing changed in Kubernetes. The change is only inside the `tester` proxy. The grader needs at least 32 of 40 requests to return `200`.

## Step 7: Watch the ejection end

Do this once, so you recognise the pattern and do not mistake it for a fault. The loop prints `ejections_active` and `ejections_total`, sends 20 requests and waits 10 seconds, six times. That takes about a minute, which is longer than the 30-second `baseEjectionTime`. Like the counters in step 5, it needs a pod that keeps the counters:

```sh
for i in 1 2 3 4 5 6; do
  kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null | grep -E 'httpbin.*ejections_(active|total)' | awk -F': ' '{printf "%s ", $2}'
  echo
  kubectl -n outlier-demo exec deploy/tester -- sh -c \
    'for i in $(seq 1 20); do curl -s -o /dev/null http://httpbin:8000/get; done'
  sleep 10
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

The first number is `ejections_active`, the second is `ejections_total`. `active` drops to `0` when the ejection time is over. The proxy then tries the endpoint again, it fails again, and the proxy ejects it again, this time for twice as long. `total` only goes up. A pod that stays broken produces this cycle, not a stable state.

## Common mistakes

- **Leaving `maxEjectionPercent` at its default.** One of two endpoints is 50% of the pool, more than the 10% default. This is the most common reason the task fails.
- **Testing with too few requests.** Each endpoint counts only the requests that reach it. You need several times `consecutive5xxErrors` requests before the bad endpoint has failed enough times in a row.
- **Deleting or scaling `httpbin-bad`.** The grader checks that it is still running. The proxy must be the one that stops using it.
- **Adding a `VirtualService` with retries.** Retries would hide the failures that outlier detection needs to see, and the grader fails any `VirtualService` in the namespace.
- **Looking at `kubectl get endpoints` for proof.** It never changes. Use the proxy's endpoint list and health flags.
- **Checking at the wrong moment.** The ejection ends after `baseEjectionTime`. If no endpoint shows `FAILED`, send more requests and check again.
- **Setting `minHealthPercent` high.** At 60% with two endpoints, ejecting one would drop the healthy share to 50%, and the proxy then switches outlier detection off.
