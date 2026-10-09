# Overview: Outlier Detection And Endpoint Ejection (Playground)

This is a **playground**: a practice cluster, not a graded lab. The cluster starts, installs Istio, deploys the workloads below, and then waits. There is no task, no `astrona submit` and no pass or fail. Try things, break things, run `astrona destroy` and start again.

## What is in the playground

The playground is one Kubernetes cluster with Istio and a small sample app:

- A single-node `kind` cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-040-03`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the custom resource definitions) and `istiod`, Istio's control plane, which sends configuration to every sidecar proxy. There is no ingress or egress gateway.
- Access logs switched on for the whole mesh, so every sidecar proxy writes one line per request.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, which holds:
  - `probe-v1` and `probe-v2`: two healthy pods of an HTTP echo server, both behind one Service `probe` on port `8000`. The `/get` path answers `200`.
  - `shuttle`: the test client pod you send single requests from. Its sidecar proxy keeps the `outlier_detection.*` counters for each destination, because the pod has the annotation `sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"`.
  - `fortio`: a load generator that sends many requests at the same time. It has the same annotation.
- Every pod shows `2/2`: the application container plus its `istio-proxy` container, the sidecar proxy (Envoy).
- **No broken pod and no `DestinationRule` yet.** You add the broken pod yourself, so you see the problem before the fix.

## Helpers

Paste these once in each new terminal. Each comment says what the helper does:

```sh
# 15 single requests from the shuttle to the probe, counted by status code
count_status() { for i in $(seq 1 15); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/get
done | sort | uniq -c; }
# the probe's endpoints as the shuttle's proxy sees them, with the OUTLIER CHECK column
show_endpoints() { istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000||probe.starfleet.svc.cluster.local"; }
# the shuttle proxy's outlier-detection counters for the probe
ejection_stats() { kubectl exec -n starfleet deploy/shuttle -c istio-proxy -- \
  pilot-agent request GET stats 2>/dev/null | grep -E 'probe.starfleet.*outlier_detection.ejections_(active|total|enforced_consecutive_5xx):'; }
# 30 requests to the probe over N parallel connections, from fortio
load_test() { kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"; }
```

## Things to try

- Add a pod with the label `app: probe` that answers every request with `503` (the image `hashicorp/http-echo:1.0` with the arguments `-listen=:8080` and `-status-code=503` does this). Run `count_status`, then add a `DestinationRule` with `outlierDetection` and run it twice.
- Compare `kubectl get endpointslices -n starfleet -l kubernetes.io/service-name=probe` with `show_endpoints`. Kubernetes still lists the broken pod, while the `shuttle` proxy shows it with `OUTLIER CHECK: FAILED`.
- Restart `deploy/shuttle` to clear its ejection history, set `maxEjectionPercent: 10`, and confirm that nothing is ever ejected with three endpoints. `ejections_overflow` in the proxy's statistics counts the blocked attempts.
- Watch `ejections_active` change between `1` and `0` while `ejections_total` only goes up.
- Set `minHealthPercent: 70` and explain why the broken pod gets requests again after the first ejection.
- Compare the `shuttle` proxy's `show_endpoints` with the same command against `deploy/fortio`. Each proxy makes its own decision.

## Start over without a new cluster

These commands delete every `DestinationRule` in `starfleet` and the broken probe Deployments, if they exist:

```sh
kubectl delete destinationrule --all -n starfleet
kubectl delete deploy probe-broken probe-broken-500 -n starfleet --ignore-not-found
```

## When you are done

`astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-040-03
```

## Practice tasks

This exam-style task combines both halves of a circuit breaker: a connection pool, which limits how many connections and waiting requests a client proxy may have open, and outlier detection, which ejects endpoints that keep failing. Paste the helpers first; the solution uses `load_test`.

Try it on your own first, then open the solution. The solution was run and checked on a real cluster set up like this playground.

> Limit clients of the `probe` to **2** connections and **1** waiting request,
> with one request per connection. Eject an endpoint for **30s** after **2** 5xx
> responses in a row, but never more than half of the endpoints. Prove the limit with `fortio`.

<details><summary>Solution</summary>

Both halves go in one `DestinationRule`, because two rules for one host do not combine reliably.

Save this as `destinationrule-probe-practice.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp: {maxConnections: 2}
      http: {http1MaxPendingRequests: 1, maxRequestsPerConnection: 1}
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

Apply it:

```bash
kubectl apply -f destinationrule-probe-practice.yaml
```

Then check the result:

```bash
load_test 5
load_test 1
```

```text
Code 200 : 9 (30.0 %)
Code 503 : 21 (70.0 %)
Code 200 : 30 (100.0 %)
```

Five parallel connections overflow a pool of 2 connections plus 1 waiting slot, so the proxy refuses most requests with `503 UO`. One connection at a time never overflows.

</details>

### Exam cheat sheet

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1     # without this: no overflow
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5          # 5 as soon as the block exists; 0 = off
      consecutiveGatewayErrors: 0      # 502/503/504 only
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50           # default 10: too low for a small service
```

- Overflow shows as **503 `UO`** in the client proxy's access log; an ejected endpoint shows as `OUTLIER CHECK FAILED` in `istioctl proxy-config endpoints`.
- Limits and ejections apply in each client's proxy, not to the Service as a whole.
- When a correct-looking rule ejects nothing, read `ejections_overflow` first.
