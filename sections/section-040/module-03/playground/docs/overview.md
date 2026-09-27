# Overview: Outlier Detection And Endpoint Ejection (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, runs
`bootstrap/prepare.sh`, applies the starting workloads, and then waits. There is
no task, no `astrona submit`, and no pass/fail. Explore, break things,
`astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it.
- **Istio 1.30.5** (`demo` profile) and `istioctl` on your PATH.
- Namespace **`outlier-demo`**, injected, containing:
  - `httpbin-good` — one replica that answers normally.
  - `httpbin-bad` — one replica of nginx configured to return **503 to
    everything**. Kubernetes considers it perfectly ready, which is the whole
    point.
  - `httpbin` — one Service on port 8000 in front of both.
  - `tester` — a client pod with `curl`.
- **No `DestinationRule`**, so half the traffic fails.

## Things to try

- Send 20 requests with no policy and count the 503s. Then apply
  `outlierDetection` and send 60, and find the point in the sequence where the
  failures stop.
- Leave `maxEjectionPercent` at its 10% default with two endpoints and confirm
  nothing is ever ejected. This is the most common silent failure.
- Watch `outlier_detection.ejections_active` flip between 1 and 0 as
  `baseEjectionTime` expires and the bad endpoint is retried, while
  `ejections_total` only climbs.
- Compare `kubectl get endpoints httpbin` with
  `istioctl proxy-config endpoints deploy/tester -n outlier-demo --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"`.
  Kubernetes and the proxy disagree, and that disagreement is the feature.
- Set `minHealthPercent: 60` with two endpoints and explain why ejection stops.
- Add `consecutiveGatewayErrors` and drive 502s instead of 503s.
- Add a retry policy on top and confirm the caller stops seeing failures
  entirely while the proxy still collects the evidence it needs to eject.

## When you're done

```sh
astrona destroy ats-014-playground-040-03
```

(`astrona destroy` takes the environment name, not the config path.)
