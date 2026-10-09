# Overview: Locality Load Balancing And Failover (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, a client pod and an HTTP echo server in two zones, and then waits. There is no task, no `astrona submit` and no pass or fail. Try things, break things, run `astrona destroy`, and start over.

## What is in the playground

The playground has one cluster with Istio and a small set of workloads:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it. The node has the labels region `local` and zone `zone-a`.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only). `istiod` is Istio's control plane: it sends configuration to every sidecar proxy.
- Mesh-wide **access logs**: every sidecar proxy writes one line for each request it handles.
- Namespace **`starfleet`**, with sidecar injection switched on:
  - **`shuttle`**, the test client pod. It runs in the node's locality, `local/zone-a`.
  - **`probe-zone-a`** and **`probe-zone-b`**: the HTTP echo server in two zones, behind one `probe` Service on port `8000`. Each pod sets its locality with the `istio-locality` pod label. `/hostname` returns the pod's name.
  - **`probe-zone-a-damaged`**: a pod in `local/zone-a` that returns `503` to every request but stays ready. It starts at 0 replicas.
- **No `DestinationRule`.** A `DestinationRule` sets the traffic policy for one host, and writing one is the point of the module.

The playground has one node, so locality does not come from real nodes in different zones. Each probe sets its own locality with the `istio-locality` label instead. All locality settings behave the same, but there is no real distance between zones, and there is only one region.

## Helpers

Paste these once in each new terminal. `count_zones` counts which probe answered, and `status_codes` prints the HTTP status code of 20 requests:

```sh
count_zones() { for i in $(seq 1 ${1:-20}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]' || echo failed
done | sort | uniq -c; }
status_codes() { kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname; done; echo'; }
```

## Start over

To undo your changes, remove your `DestinationRule` and set the probe Deployments back to their starting replica counts:

```sh
kubectl delete destinationrule probe -n starfleet
kubectl -n starfleet scale deployment probe-zone-a-damaged --replicas=0
kubectl -n starfleet scale deployment probe-zone-a --replicas=1
```

## When you are done

Remove the playground. `astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-040-04
```

## Practice tasks

Each task below is a small change to the `DestinationRule` files you saved while reading the module. Edit the file, apply it with `kubectl apply -f`, and check what happens.

- Run `count_zones 20` with no `DestinationRule`. Then add only `localityLbSetting: {enabled: true}` and run it again. Then add `outlierDetection`. Only the last version keeps every request in `zone-a`.
- In the `distribute` file, try 50/50 and 90/10, and measure each with `count_zones 100`.
- Lower `maxEjectionPercent` to `10` in the failover `DestinationRule`, scale `probe-zone-a-damaged` up, and check whether the requests still leave `zone-a`.
- Scale `probe-zone-a` to 0, and compare the result with scaling `probe-zone-a-damaged` up: the first is endpoint removal, the second is endpoint failure.
- Run `istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000||probe.starfleet.svc.cluster.local"` while `probe-zone-a-damaged` is running, and watch its `OUTLIER CHECK` column.
