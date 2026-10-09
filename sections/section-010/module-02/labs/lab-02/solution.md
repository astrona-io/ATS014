# Solution Walkthrough

Mission debrief, astronaut. The planet default was correct all along. The shuttle's own `Sidecar` replaced it, and that `Sidecar` listed only the shuttle's own planet. Here is how to find that and repair it.

## Step 1: See the failure

Send a signal from the shuttle to the probe, and read the shuttle's flight log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://probe.outpost:8000/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
000
command terminated with exit code 56
[2026-10-08T20:09:46.799Z] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 10.96.9.72:8000 10.244.0.6:47394 - -
```

`000` means no answer at all, and `BlackHoleCluster` with `UH` means the shuttle's communications officer has no destination for this host. Under `REGISTRY_ONLY`, an uncharted host falls into the black hole.

## Step 2: Compare the shuttle with a ship that works

The cargo ship lives on the same planet. Compare the two star charts:

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

The shuttle knows only `cargo`. The cargo ship knows `istiod` and the probe too. Same planet, different charts: so a different `Sidecar` applies to the shuttle.

## Step 3: Find the `Sidecar` that wins

List the `Sidecar` objects on the planet, and read the shuttle's own:

```sh
kubectl get sidecar -n starfleet
kubectl get sidecar shuttle-only -n starfleet -o yaml
```

```text
NAME           AGE
default        16s
shuttle-only   16s
```

Trimmed to `spec`:

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

`shuttle-only` selects the shuttle, so it beats the planet default. A selector `Sidecar` **replaces** the planet default; it inherits nothing. It lists only `./*`, so the shuttle lost `istio-system` and `outpost`.

## Step 4: Repair it

Keep the selector and `REGISTRY_ONLY`, and list everything the shuttle needs. Save this as `sidecar-shuttle-only.yaml`:

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

## Step 5: Prove it

Check the shuttle's star chart, then send signals to the probe and the cargo ship:

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

The probe and `istiod` are back on the shuttle's chart. The signal leaves through `outbound|8000||probe.outpost.svc.cluster.local`, its own destination, not a passthrough. Submit:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-02
```

## Mistakes that fail the grader

- **Deleting `shuttle-only`.** The probe becomes reachable through the planet default, but the task is to repair the shuttle's own `Sidecar`.
- **Adding only `outpost/*`.** The shuttle still lacks `istio-system/*`. A selector `Sidecar` must list it itself.
- **Removing `outboundTrafficPolicy` from `shuttle-only`.** The shuttle falls back to `ALLOW_ANY` and the probe answers through `PassthroughCluster`. That is not the probe's own destination.
- **Changing the planet default.** It was correct. Change only `shuttle-only`.
- **Relabelling the shuttle** so the selector no longer matches. The grader checks the shuttle still carries `app: shuttle`.
