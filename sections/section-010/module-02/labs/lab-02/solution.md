# Solution Walkthrough

The namespace-wide `Sidecar` was correct all along. The `shuttle` pod's own `Sidecar` replaced it, and that `Sidecar` listed only the pod's own namespace. The steps below find that and repair it.

## Step 1: See The Failure

Send a request from `shuttle` to `probe`, and read the last line of the `shuttle` proxy's access log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://probe.outpost:8000/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
000
command terminated with exit code 56
[2026-10-08T20:09:46.799Z] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 10.96.9.72:8000 10.244.0.6:47394 - -
```

`000` means no response at all. `BlackHoleCluster` with the flag `UH` means the `shuttle` proxy has no destination for this host. Under `REGISTRY_ONLY`, the proxy sends a request for an unknown host to the `BlackHoleCluster`, which drops it.

## Step 2: Compare With A Workload That Works

`cargo` runs in the same namespace. Compare the cluster lists of the two proxies:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -E "SERVICE|outpost|istiod|cargo"
istioctl proxy-config cluster deploy/cargo-v1 -n starfleet | grep -E "outpost|istiod"
```

```text
SERVICE FQDN                          PORT     SUBSET     DIRECTION     TYPE             DESTINATION RULE
cargo.starfleet.svc.cluster.local     9080     -          outbound      EDS
istiod.istio-system.svc.cluster.local     443       -          outbound      EDS
istiod.istio-system.svc.cluster.local     15010     -          outbound      EDS
istiod.istio-system.svc.cluster.local     15012     -          outbound      EDS
istiod.istio-system.svc.cluster.local     15014     -          outbound      EDS
probe.outpost.svc.cluster.local           8000      -          outbound      EDS
```

The `shuttle` proxy knows only `cargo`. The `cargo-v1` proxy also knows `istiod` and `probe`. Both pods are in the same namespace but have different configuration, so a different `Sidecar` applies to `shuttle`.

## Step 3: Find The Sidecar That Applies

List the `Sidecar` objects in the namespace, and read the one for `shuttle`:

```sh
kubectl get sidecar -n starfleet
kubectl get sidecar shuttle-only -n starfleet -o yaml
```

```text
NAME           AGE
default        16s
shuttle-only   16s
```

The second command, shortened to `spec`:

```text
spec:
  egress:
  - hosts:
    - ./*
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  workloadSelector:
    labels:
      app: shuttle
```

`shuttle-only` selects the `shuttle` pod, so `istiod` uses it instead of the namespace-wide `default`. A selector `Sidecar` **replaces** the namespace default; it takes nothing from it. It lists only `./*`, so the `shuttle` proxy lost `istio-system` and `outpost`.

## Step 4: Repair It

Keep the selector and `REGISTRY_ONLY`, and list every host the `shuttle` pod needs. Save this as `sidecar-shuttle-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: shuttle-only
  namespace: starfleet
spec:
  workloadSelector:
    labels:
      app: shuttle
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
    - "outpost/*"
```

Apply it:

```sh
kubectl apply -f sidecar-shuttle-only.yaml
```

```text
sidecar.networking.istio.io/shuttle-only configured
```

## Step 5: Prove It

Check the `shuttle` proxy's clusters, then send requests to `probe` and `cargo`:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -E "outpost|istiod|cargo"
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe.outpost:8000/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
```

```text
cargo.starfleet.svc.cluster.local         9080      -          outbound      EDS
istiod.istio-system.svc.cluster.local     443       -          outbound      EDS
istiod.istio-system.svc.cluster.local     15010     -          outbound      EDS
istiod.istio-system.svc.cluster.local     15012     -          outbound      EDS
istiod.istio-system.svc.cluster.local     15014     -          outbound      EDS
probe.outpost.svc.cluster.local           8000      -          outbound      EDS
200
[2026-10-08T20:10:08.695Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 655 7 6 "-" "curl/8.11.1" "d4ada470-7c8b-4e28-93be-a1fac87436f9" "probe.outpost:8000" "10.244.0.8:8080" outbound|8000||probe.outpost.svc.cluster.local 10.244.0.6:58786 10.96.9.72:8000 10.244.0.6:35556 - default
200
```

The `probe` and `istiod` clusters are back in the `shuttle` proxy. The request leaves through `outbound|8000||probe.outpost.svc.cluster.local`, the cluster of the `probe` Service, not through a passthrough. Submit:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-02
```

## Mistakes That Fail The Grader

- **Deleting `shuttle-only`.** `probe` becomes reachable through the namespace default, but the task is to repair the `shuttle` pod's own `Sidecar`.
- **Adding only `outpost/*`.** The `shuttle` proxy still lacks `istio-system/*`. A selector `Sidecar` must list it itself.
- **Removing `outboundTrafficPolicy` from `shuttle-only`.** The `shuttle` pod falls back to `ALLOW_ANY`, and `probe` answers through `PassthroughCluster`. That is not the cluster of the `probe` Service.
- **Changing the namespace default.** It was correct. Change only `shuttle-only`.
- **Changing the `shuttle` pod labels** so the selector no longer matches. The grader checks that the pods still carry `app: shuttle`.
