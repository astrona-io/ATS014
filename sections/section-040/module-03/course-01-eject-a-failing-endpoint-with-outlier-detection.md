# Eject A Failing Endpoint With Outlier Detection

A pod can be `Running`, pass every check Kubernetes makes, and still answer every request with an error. Kubernetes keeps sending it traffic, because it never looks at the responses. This part shows that problem on a real cluster, and then fixes it with **outlier detection**: an Istio setting that makes the client's proxy stop sending requests to an endpoint that keeps failing.

## A ready pod that fails every request

Kubernetes decides which pods belong to a Service by two things: their labels and their readiness. A pod is **ready** when its readiness probe passes, or when it has no readiness probe at all. A **readiness probe** is a health check that the kubelet, the Kubernetes agent on each node, runs against the pod on a schedule. Kubernetes never looks at the responses a pod gives to real requests, so a pod can be ready and still fail every one of them.

The next step creates exactly that pod. It gives the problem a concrete shape before you meet the fix.

<!-- astrona:playground:renew -->

The commands in this part use one shell helper function, `count_status`. Paste it into your terminal first. It sends 15 requests from the `shuttle` pod to the `probe` Service and counts the responses by HTTP status code:

```sh
# 15 single requests from the shuttle to the probe, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c; }
```

The new Deployment adds a third pod behind the `probe` Service. It carries the same `app: probe` label, so the Service sends it a share of the requests. Its container answers **every** request with HTTP status `503`, and it has no readiness probe that could fail. Save this as `deployment-probe-broken.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-broken
  namespace: starfleet
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probe
      version: broken
  template:
    metadata:
      labels:
        app: probe
        version: broken
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:1.0
        args:
        - -listen=:8080
        - -status-code=503
        - -text=broken
        ports:
        - containerPort: 8080
```

Apply it:

```sh
kubectl apply -f deployment-probe-broken.yaml
```

Then wait for the rollout, list the probe pods, and send 15 requests:

```sh
kubectl rollout status -n starfleet deploy/probe-broken
kubectl get pods -n starfleet -l app=probe
count_status
```

You should see this (the waiting lines of the rollout are left out):

```text
deployment "probe-broken" successfully rolled out
NAME                            READY   STATUS    RESTARTS   AGE
probe-broken-5d7dc9b96f-zcpgs   2/2     Running   0          5s
probe-v1-7888d6c6d5-tct6g       2/2     Running   0          34s
probe-v2-58767cc46-rvjn5        2/2     Running   0          34s
   9 200
   6 503
```

All three pods show `2/2 Running`, so Kubernetes treats them as equally healthy. Still, a share of the requests fails. Your numbers will differ a little on each run, because the load balancer picks the broken pod at random for some requests.

## Active and passive health checks

The pod you just created shows why a second kind of health check is needed. A readiness probe and outlier detection both decide which pods get requests, but they work in opposite ways:

| | Readiness probe (Kubernetes) | Outlier detection (Istio) |
| --- | --- | --- |
| Kind | **active**: sends test requests on a schedule | **passive**: watches real requests |
| Who decides | the kubelet, for each pod | each client's sidecar proxy, on its own |
| What it checks | "does the pod say it is ready?" | "have the responses to *this proxy* been failing?" |
| Effect | removes the pod from the Service, for every client | removes the endpoint from **one proxy's** load-balancing pool |
| Catches | a pod that knows it is broken | a pod that does not know it is broken |

The **sidecar proxy** is the Envoy container that Istio adds to each pod. All traffic in and out of the pod passes through it. An **endpoint** is one pod address and port behind a Service, and the proxy's **load-balancing pool** is the list of endpoints it chooses from for each request.

The last row of the table is the reason outlier detection exists. A readiness probe is a question the pod answers about itself. A pod with a broken dependency answers it correctly and still fails every real request.

Passive checking has a cost that follows from how it works: **it needs real failures before it can act.** Its evidence is failed requests from real clients. It cannot find a bad endpoint before that endpoint has failed some requests.

## The fields that mark an endpoint as failing

You configure outlier detection in a `DestinationRule`, the Istio object that sets traffic policy for requests to one host. The settings go under `trafficPolicy.outlierDetection`. Three fields decide when an endpoint counts as failing:

- **`consecutive5xxErrors`**: how many 5xx responses (HTTP status codes from 500 to 599) **in a row from the same endpoint** mark it as failing. One successful response from that endpoint resets its count to zero. The value is 5 as soon as an `outlierDetection` block exists. Set it to `0` to switch it off.
- **`consecutiveGatewayErrors`**: the same idea, but it only counts `502`, `503` and `504`. Use it when errors from inside the application (`500`) should not count. It is off (`0`) unless you set it.
- **`consecutiveLocalOriginFailures`**: counts failures that the proxy saw itself, such as a refused or reset connection, instead of status codes. It works together with `splitExternalLocalOriginErrors`.

Four more fields, `interval`, `baseEjectionTime`, `maxEjectionPercent` and `minHealthPercent`, decide what happens after an endpoint is marked. When the proxy removes a failing endpoint from its pool for a while, this is called an **ejection**.

## Counting per endpoint, in a row

The two words "consecutive" and "per endpoint" decide how fast the proxy catches a bad endpoint.

The count is **per endpoint**. Each endpoint has its own counter, and only its own responses change it. Successful responses from the healthy pods do not reset the broken pod's count. The count is also **consecutive**: one success *from that endpoint* resets it to zero.

So an endpoint that fails **every** request is caught quickly. With `consecutive5xxErrors: 3`, the load balancer only has to pick it three times, whenever that happens. The healthy endpoints around it do not slow that down.

An endpoint that fails only *some* requests is different. If it fails every second request, its successes keep resetting the count. It may never reach the limit, even though half its responses are errors. Consecutive counting catches an endpoint that is fully broken, and it is weak against one that is only partly broken.

## Apply the first outlier detection rule

Now you can write the rule. It marks an endpoint as failing after three 5xx responses in a row, and allows half of the endpoints to be ejected at the same time. Save this as `destinationrule-probe-outlier-detection.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 1m
      maxEjectionPercent: 50
```

Apply it:

```sh
kubectl apply -f destinationrule-probe-outlier-detection.yaml
```

Then send two rounds of 15 requests:

```sh
count_status
count_status
```

You should see:

```text
  12 200
   3 503
  15 200
```

In the first round, the broken pod still got requests. Its three `503` responses in a row were the evidence. Then the `shuttle` pod's sidecar proxy removed that endpoint from its own load-balancing pool, and the second round had no errors.

You now know what outlier detection is, how it differs from a readiness probe, and which fields mark an endpoint as failing. The ejection itself still needs a closer look: how long it lasts, which errors count, and what can stop it from happening at all.

## Common pitfalls

> [!WARNING]
> - **Expecting outlier detection to catch a bad endpoint before it fails.** It is passive: it learns from real failed requests, so something has to fail first.
> - **Using outlier detection instead of readiness probes.** They check different things. A readiness probe removes a pod from the Service for every client. An ejection removes an endpoint from one proxy's pool.
> - **Reading `Running` and `2/2` as "the pod answers correctly".** A pod in that state can still fail every request.
> - **Expecting consecutive counting to catch an endpoint that fails only sometimes.** Each success from that endpoint resets its count.
> - **Configuring it for a Service with one endpoint.** There is no other endpoint to send requests to, so an ejection cannot help.
