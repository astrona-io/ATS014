# Overview: Connection Timeouts, Keepalive And Nearby Endpoints (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, a client pod and an HTTP echo server in two zones, and then waits. There is no task, no `astrona submit` and no pass or fail. Try things, break things, run `astrona destroy`, and start over.

## What is in the playground

The playground has one cluster with Istio and a small set of workloads:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it. The node has the labels region `local` and zone `zone-a`.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only). `istiod` is Istio's control plane: it sends configuration to every sidecar proxy.
- Mesh-wide **access logs**: every sidecar proxy writes one line for each request it handles.
- Namespace **`starfleet`**, with sidecar injection switched on:
  - **`shuttle`**, the test client pod. It runs in the node's locality, `local/zone-a`.
  - **`probe-zone-a`** and **`probe-zone-b`**: the HTTP echo server in two zones, behind one `probe` Service on port `8000`. Each pod sets its locality with the `istio-locality` pod label. `/hostname` returns the pod's name, and `/delay/<seconds>` waits before it answers.
  - **`probe-zone-a-damaged`**: a pod in `local/zone-a` that returns `503` to every request but stays ready. It starts at 0 replicas.
- **No `DestinationRule`, no `VirtualService` and no `trafficDistribution`.** Setting them is the point of the module.

The playground has one node, so locality does not come from real nodes in different zones. Each probe sets its own locality with the `istio-locality` label instead. The locality settings behave the same, but there is no real distance between zones.

## Helpers

Two helper scripts ship with this playground. `count-zones.sh` sends requests from `shuttle` to the probe and counts which zone answered. `show-connection-settings.sh` prints the connect timeout, idle timeout, maximum connection duration and keepalive settings that the proxy of `shuttle` holds for the probe.

```sh
astrona res run count-zones.sh -- 20
astrona res run show-connection-settings.sh
```

## Start over

To undo your changes, remove the objects you created and set the probe Deployments back to their starting replica counts. Replace the `Service` with a version that has no `trafficDistribution`:

```sh
kubectl delete destinationrule probe -n starfleet --ignore-not-found
kubectl delete virtualservice probe -n starfleet --ignore-not-found
kubectl patch service probe -n starfleet --type json -p '[{"op":"remove","path":"/spec/trafficDistribution"}]'
kubectl -n starfleet scale deployment probe-zone-a-damaged --replicas=0
kubectl -n starfleet scale deployment probe-zone-a --replicas=1
```

The last `kubectl patch` prints an error when the `Service` has no `trafficDistribution` yet. That is harmless.

## When you are done

Remove the playground. `astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-040-05
```

## Practice tasks

Each task below is a small change to the files you saved while reading the module. Edit the file, apply it with `kubectl apply -f`, and check what happens.

- Change `connectTimeout` to `500ms`, apply the `DestinationRule`, and run `astrona res run show-connection-settings.sh`. Check that the proxy now holds the new value.
- Set `idleTimeout: 5s`, apply it, and check the cluster JSON. Then set `maxConnectionDuration: 30s` and check it appears under a different name than `idleTimeout`.
- Change the keepalive `probes` to `2` and the `time` to `30s`, and find both values in the cluster JSON.
- Remove the whole `connectionPool` block and apply the `DestinationRule` again. Read the connect timeout from the proxy and compare it with the value from before you created any `DestinationRule`.
- Run `astrona res run count-zones.sh -- 20` with no `trafficDistribution`. Then set `trafficDistribution: PreferClose` on the `probe` Service and run it again. Remove the field and run it a third time.
- Set `PreferClose`, scale `probe-zone-a` to 0, and send requests. Check that they reach `probe-zone-b` and stay without errors, because the pod has left the endpoint list.
- Set `PreferClose`, add the `outlierDetection` `DestinationRule`, scale `probe-zone-a` to 0 and `probe-zone-a-damaged` to 1, and send 20 requests. Explain why the first requests fail and the later ones do not, using the `OUTLIER CHECK` column of `istioctl proxy-config endpoints`.
