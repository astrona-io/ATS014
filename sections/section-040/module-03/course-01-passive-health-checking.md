# Passive Health Checking

> **Before you start:** define the helper functions from [the landing page](./course.md#before-you-start).

Astronaut, this part shows what the mechanism is, what it watches, and why it catches a kind of failure that Kubernetes cannot see: a ship that reports "all green" but drops your signals.

## The problem, made visible

Add a third pod behind the `httpbin` Service. It carries the same `app: httpbin` label, so the Service sends it a share of the traffic. But it answers **every** request with a 503. It never fails a readiness probe, because it has none to fail.

> [!TIP]
> **Try it — a Service with one broken endpoint**
>
> ```sh
> cat > httpbin-broken-pod.yaml <<'EOF'
> apiVersion: apps/v1
> kind: Deployment
> metadata:
>   name: httpbin-broken
>   namespace: bookinfo
> spec:
>   replicas: 1
>   selector:
>     matchLabels:
>       app: httpbin
>       version: broken
>   template:
>     metadata:
>       labels:
>         app: httpbin
>         version: broken
>     spec:
>       containers:
>       - name: http-echo
>         image: hashicorp/http-echo:1.0
>         args:
>         - -listen=:8080
>         - -status-code=503
>         - -text=broken
>         ports:
>         - containerPort: 8080
> EOF
> kubectl apply -f httpbin-broken-pod.yaml
> kubectl rollout status -n bookinfo deploy/httpbin-broken
> kubectl get pods -n bookinfo -l app=httpbin
> count_status
> ```
>
> Expect all three `httpbin` pods to show `2/2 Running`, and a count like:
>
> ```text
>   12 200
>    3 503
> ```
>
> Your split will vary a little. Kubernetes treats all three pods as equally healthy, and still about a third of the requests fail.

## Active versus passive

The difference is worth stating exactly, because it shapes the whole module.

| | Readiness probe (Kubernetes) | Outlier detection (Istio) |
| --- | --- | --- |
| Kind | **active**: test requests on a schedule | **passive**: watches real traffic |
| Who decides | the kubelet, per pod | each caller's sidecar, on its own |
| What it asks | "do you say you are ready?" | "have your answers to *me* been failing?" |
| Effect | takes the pod out of the Service, for everyone | takes the endpoint out of **one proxy's** load-balancing set |
| Catches | a pod that knows it is broken | a pod that does not know, or claims it is fine |

People underestimate the second row, and Part 3 comes back to it. The last row is why this module exists. A probe is a question the pod answers about itself. A pod with a dead dependency will answer it correctly and still fail every real request.

Passive checking has a cost that follows from how it works: **it needs real failures to notice anything.** The evidence is other people's failed requests. There is no way to spot a bad endpoint before it has broken something.

## The fields

The settings live in a `DestinationRule`, under `trafficPolicy.outlierDetection`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: bookinfo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 1m
      maxEjectionPercent: 50
```

The fields that decide what counts as a failing endpoint:

- **`consecutive5xxErrors`** — how many 5xx answers **in a row from the same endpoint** mark it as failing. A single success from that endpoint resets its count to zero. It defaults to 5 as soon as an `outlierDetection` block exists. Set it to `0` to switch it off.
- **`consecutiveGatewayErrors`** — the same idea, but it only counts 502, 503 and 504. Use it when application 500s should not count. It is off (`0`) by default. Part 2 shows the trap in combining the two.
- **`consecutiveLocalOriginFailures`** — counts failures the proxy saw itself (connection refused, reset) instead of status codes. It is used with `splitExternalLocalOriginErrors`.

The other fields, `interval`, `baseEjectionTime`, `maxEjectionPercent` and `minHealthPercent`, decide what *happens* once an endpoint is marked. They are Part 2.

## "Consecutive" and "per endpoint"

Both words matter, and together they decide how fast a bad endpoint is caught.

The count is **per endpoint**: each endpoint has its own counter, fed only by its own answers. Answers from the healthy pods do not reset the broken pod's count. And it is **consecutive**: a success *from that endpoint* resets it.

So a pod that fails **every** request is caught quickly. It only has to be picked three times, whenever that happens, for `consecutive5xxErrors: 3` to mark it. Healthy pods around it do not slow that down.

A pod that fails only *some* requests is a different story. If it fails every other request, its successes keep resetting the count, and it may never reach the threshold even though half its answers are errors. Consecutive counting catches a pod that is fully broken. It is weak against a pod that is partly broken.

> [!TIP]
> **Try it — apply the detection and watch the failures stop**
>
> ```sh
> cat > destinationrule-httpbin-outlier-detection.yaml <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: DestinationRule
> metadata:
>   name: httpbin
>   namespace: bookinfo
> spec:
>   host: httpbin
>   trafficPolicy:
>     outlierDetection:
>       consecutive5xxErrors: 3
>       interval: 5s
>       baseEjectionTime: 1m
>       maxEjectionPercent: 50
> EOF
> kubectl apply -f destinationrule-httpbin-outlier-detection.yaml
> count_status
> count_status
> ```
>
> Expect a few 503s in the first run, while the sidecar is still counting the broken pod's errors. Then the second run shows:
>
> ```text
>   15 200
> ```
>
> The broken pod gave three 503s in a row, so the caller's sidecar took it out of its own pool. Part 3 shows where you can see that.

## Common pitfalls

> [!WARNING]
> **Expecting it to catch a bad endpoint before it breaks anything.** Passive means it learns from real failed requests. Something has to fail first.
>
> **Treating it as a replacement for readiness probes.** They answer different questions. A probe takes a pod out of the Service for everyone. An ejection takes an endpoint out of one proxy's load-balancing set.
>
> **Expecting `Running` and `2/2` to mean a pod serves correctly.** That is exactly the case this module exists for.
>
> **Expecting consecutive counting to catch a pod that fails only sometimes.** Each success from that pod resets its count.
>
> **Configuring it on a Service with one endpoint.** With nothing else to send to, there is nothing it can usefully eject.

> *Passive means the evidence is other people's failed requests: nothing is detected until something has already broken.*
