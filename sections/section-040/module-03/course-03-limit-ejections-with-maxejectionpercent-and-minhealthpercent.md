# Limit Ejections With maxEjectionPercent And minHealthPercent

A feature that removes failing endpoints must never remove *all* of them. If a shared dependency fails, every pod of a Service starts to answer with 5xx errors at the same time. Outlier detection without limits would then eject every endpoint, and a slow Service would become a Service that is completely down. This part covers the two fields that prevent that, and shows why the default of one of them stops every ejection on a small Service.

The commands in this part start from a known state. The `starfleet` namespace has the `probe` Service with two healthy pods (`probe-v1` and `probe-v2`) and a third pod, `probe-broken`, that answers every request with `503`. Its Deployment is saved in `deployment-probe-broken.yaml`. A `DestinationRule` named `probe`, saved in `destinationrule-probe-outlier-detection.yaml`, has this outlier detection block: `consecutive5xxErrors: 3`, `interval: 5s`, `baseEjectionTime: 1m` and `maxEjectionPercent: 50`.

## The two safety limits

Outlier detection runs inside each client's sidecar proxy, the Envoy container that Istio adds to each pod. When the proxy **ejects** an endpoint (one pod address and port), it removes that endpoint from its load-balancing pool for a while. Two fields under `trafficPolicy.outlierDetection` limit how far this can go.

**`maxEjectionPercent`** sets the largest share of the pool that may be ejected at the same time. Its default is **10%**.

That default is the most common reason a correct-looking rule does nothing. Before each ejection, Envoy works out what share of the pool *would* be ejected after it. With three endpoints, ejecting one means 33%. That is above 10%, so Envoy ejects nothing. On any small Service, the rule runs, counts the failures, and never ejects anything, and no error message tells you so.

On a small Service you must raise it. The value `50` allows one endpoint of three (33%) to be out, but not two (67%). The value `100` means "eject as many as are failing". That is right when you would rather send requests to no endpoint than to a failing one.

**`minHealthPercent`** works from the other side. As long as at least this share of the pool is healthy, outlier detection is active. When the healthy share drops *below* it, outlier detection switches off, and the proxy sends requests to every endpoint again, failing ones included. The default is `0%`, so it never switches off.

With three endpoints and `minHealthPercent: 70`, the first ejection leaves 67% healthy. That is below 70%, so detection switches off again at once. The field is a useful guard on a large pool and a trap on a small one.

## The 10% default on a real Service

A test shows the default at work. It needs a client proxy with no ejection history, so that old ejections do not change the result.

<!-- astrona:playground:renew -->

The commands in this part use one shell helper function, `count_status`. Paste it into your terminal first. It sends 15 requests from the `shuttle` pod to the `probe` Service and counts the responses by status code:

```sh
# 15 single requests from the shuttle to the probe, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c; }
```

Restart the `shuttle` Deployment. Its new pod gets a new sidecar proxy that starts with no ejection history:

```sh
kubectl rollout restart -n starfleet deploy/shuttle
kubectl rollout status -n starfleet deploy/shuttle
```

Then lower the limit to 10%, the same value as the default. Save this as `destinationrule-probe-10-percent.yaml`:

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
      maxEjectionPercent: 10
```

Apply it:

```sh
kubectl apply -f destinationrule-probe-10-percent.yaml
```

Then send two rounds of 15 requests, and read the proxy's outlier detection counters. `pilot-agent request GET stats` asks the Envoy in the `istio-proxy` container for its statistics. The `grep` keeps the counters for the `probe` Service, including the one that counts blocked ejections:

```sh
count_status
count_status
kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
  | grep -E 'probe.starfleet.*outlier_detection.(ejections_active|ejections_total|ejections_overflow|ejections_detected_consecutive_5xx|ejections_enforced_consecutive_5xx):'
```

You should see:

```text
  14 200
   1 503
   9 200
   6 503
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_active: 0
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_detected_consecutive_5xx: 2
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_enforced_consecutive_5xx: 0
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_overflow: 3
cluster.outbound|8000||probe.starfleet.svc.cluster.local;.outlier_detection.ejections_total: 0
```

The broken pod keeps failing in both rounds, and the counters show why. The proxy **detected** the failing endpoint twice (`detected_consecutive_5xx: 2`), but **enforced** nothing (`enforced_consecutive_5xx: 0`). Three times the limit blocked an ejection (`ejections_overflow: 3`): one endpoint of three is 33%, which is more than 10%.

Put the 50% rule back, so the proxy can eject the broken pod again:

```sh
kubectl apply -f destinationrule-probe-outlier-detection.yaml
```

> [!TIP]
> When a correct-looking outlier detection rule ejects nothing, read `ejections_overflow` first. Any number above 0 means the proxy found the failing endpoint and `maxEjectionPercent` blocked the ejection.

## From a requirement to a field

Exam tasks usually describe a behaviour, not a value. Now that you know every field, this table maps a requirement to the field you change:

| Requirement | Field to change |
| --- | --- |
| "let a failing endpoint back in sooner (or later)" | `interval` and `baseEjectionTime` |
| "tolerate a short burst of errors" | raise `consecutive5xxErrors` |
| "do not count errors from inside the application" | `consecutiveGatewayErrors`, **and** `consecutive5xxErrors: 0` |
| "keep a failing endpoint out longer each time" | nothing: Envoy multiplies `baseEjectionTime` for you |
| "it must really eject on a small Service" | raise `maxEjectionPercent` above the 10% default |
| "never remove more than half of the endpoints" | `maxEjectionPercent: 50` |
| "stop ejecting when most of the Service is down" | `minHealthPercent` |

You can now eject a failing endpoint, choose which errors count, and get past the 10% limit on a small Service. The proof so far is the status codes the client receives. The proxy's own view of each endpoint, and why Kubernetes never shows an ejection, are still open.

## Common pitfalls

> [!WARNING]
> - **Leaving `maxEjectionPercent` at 10% on a small Service.** With two or three endpoints, nothing can ever be ejected. `ejections_overflow` counts the blocked attempts.
> - **Reading `ejections_detected_consecutive_5xx` as proof of an ejection.** It only means the proxy found a failing endpoint. `ejections_enforced_consecutive_5xx` counts the ejections that really happened.
> - **Setting `minHealthPercent` high on a small Service.** One ejection can push the healthy share below it, and then detection switches off.
> - **Testing with a proxy that has old ejection history.** Restart the client Deployment first, so its counters start at zero.

## Your mission: Eject A Failing Endpoint On A Two-Endpoint Service Lab

You can now write an outlier detection rule that really ejects on a small Service. In the lab, a Service has two endpoints and one of them answers every request with `503`, and you must make the client's proxy stop using it while Kubernetes keeps listing it.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-03
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-03/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-03/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-040-03
astrona start ats-014-playground-040-03
```
