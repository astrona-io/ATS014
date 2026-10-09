# Passive Health Checking

Astronaut, this part shows the problem outlier detection solves: a ship that reports "all green" and still drops your signals. Then it shows the setting that fixes it, and why the fix is called *passive*.

The commands below need the four helpers from the module's landing page pasted into your terminal.

## The problem, made visible

Kubernetes decides which pods belong to a Service by their labels and their readiness. It never looks at the answers a pod gives to real signals. So a pod can be "ready" and still fail every one of them.

<!-- astrona:playground:renew -->

### Add a ship that fails every signal

Add a third pod behind the `probe` Service. It carries the same `app: probe` label, so the Service sends it a share of the signals. But it answers **every** signal with a `503`, and it has no readiness probe to fail. Save this as `probe-broken.yaml`:

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
kubectl apply -f probe-broken.yaml
```

Then wait for it to start, list the probe ships, and send 15 signals:

```sh
kubectl rollout status -n starfleet deploy/probe-broken
kubectl get pods -n starfleet -l app=probe
count_status
```

You should see (the rollout's waiting lines trimmed):

```text
deployment "probe-broken" successfully rolled out
NAME                            READY   STATUS    RESTARTS   AGE
probe-broken-5d7dc9b96f-zcpgs   2/2     Running   0          5s
probe-v1-7888d6c6d5-tct6g       2/2     Running   0          34s
probe-v2-58767cc46-rvjn5        2/2     Running   0          34s
   9 200
   6 503
```

All three ships show `2/2 Running`, so Kubernetes treats them as equally healthy. Still, a share of the signals fails. Your split will be a little different each run, because the broken ship gets a random share.

## Active versus passive

A readiness probe and outlier detection both decide which ships get signals, but they work in opposite ways:

| | Readiness probe (Kubernetes) | Outlier detection (Istio) |
| --- | --- | --- |
| Kind | **active**: test requests on a schedule | **passive**: watches real signals |
| Who decides | the kubelet, per pod | each sender's communications officer, on its own |
| What it asks | "do you say you are ready?" | "have your answers to *me* been failing?" |
| Effect | takes the pod out of the Service, for everyone | takes the endpoint out of **one proxy's** list of ships |
| Catches | a pod that knows it is broken | a pod that does not know, or claims it is fine |

The last row is why this module exists. A probe is a question the pod answers about itself. A pod with a dead dependency answers it correctly and still fails every real signal.

Passive checking has a cost that follows from how it works: **it needs real failures to notice anything.** Its evidence is other people's failed signals. There is no way to spot a bad ship before it has broken something.

## The fields that define a failing ship

The settings live in a `DestinationRule`, under `trafficPolicy.outlierDetection`. These three decide what counts as a failing endpoint:

- **`consecutive5xxErrors`**: how many 5xx answers **in a row from the same endpoint** mark it as failing. A single success from that endpoint resets its count to zero. It is 5 as soon as an `outlierDetection` block exists. Set it to `0` to switch it off.
- **`consecutiveGatewayErrors`**: the same idea, but it only counts `502`, `503` and `504`. Use it when errors from inside the app (`500`) should not count. It is off (`0`) unless you set it.
- **`consecutiveLocalOriginFailures`**: counts failures the proxy saw itself, such as a refused or reset connection, instead of status codes. It is used together with `splitExternalLocalOriginErrors`.

The other fields, `interval`, `baseEjectionTime`, `maxEjectionPercent` and `minHealthPercent`, decide what happens once an endpoint is marked.

## "Consecutive" and "per endpoint"

Both words decide how fast a bad ship is caught.

The count is **per endpoint**: each ship has its own counter, fed only by its own answers. Answers from the healthy ships do not reset the broken ship's count. And it is **consecutive**: a success *from that ship* resets it.

So a ship that fails **every** signal is caught quickly. It only has to be picked three times, whenever that happens, for `consecutive5xxErrors: 3` to mark it. The healthy ships around it do not slow that down.

A ship that fails only *some* signals is a different story. If it fails every other signal, its successes keep resetting the count, and it may never reach the limit, even though half its answers are errors. Consecutive counting catches a ship that is fully broken. It is weak against a ship that is partly broken.

### Pull the broken ship out of formation

Mark a ship as failing after three 5xx answers in a row. Save this as `destinationrule-probe-outlier-detection.yaml`:

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

Then send two rounds of 15 signals:

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

In the first round, the broken ship still got signals: its three `503`s in a row were the evidence. Then the shuttle's communications officer took it out of its own list of ships, and the second round was clean.

## Common pitfalls

> [!WARNING]
> - **Expecting it to catch a bad ship before it breaks anything.** Passive means it learns from real failed signals. Something has to fail first.
> - **Treating it as a replacement for readiness probes.** They answer different questions. A probe takes a pod out of the Service for everyone. An ejection takes an endpoint out of one proxy's list.
> - **Expecting `Running` and `2/2` to mean a pod answers correctly.** That is exactly the case this module exists for.
> - **Expecting consecutive counting to catch a ship that fails only sometimes.** Each success from that ship resets its count.
> - **Setting it up for a Service with one endpoint.** With no other ship to send to, there is nothing useful it can eject.

> *Passive means the evidence is other people's failed signals: nothing is detected until something has already broken.*
