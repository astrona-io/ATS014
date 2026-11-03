# Question

Solve this question on: `terminal`

Requests from the `shuttle` pod cross zones for no reason, which costs time and money. The team wants them to stay in the zone of the caller as long as an endpoint there works.

The namespace `starfleet` runs on a cluster with one node. The node has the labels region `local` and zone `zone-a`. Three Deployments run there:

| Deployment | Locality |
| --- | --- |
| `shuttle` | `local/zone-a`, the node's locality. You send every test request from here |
| `probe-zone-a` | `local/zone-a` |
| `probe-zone-b` | `local/zone-b` |

A **locality** is the region, zone and subzone a pod runs in. The probe pods set theirs with the `istio-locality` label. Both probe Deployments sit behind the `probe` Service on port `8000`. Its `/hostname` path returns the name of the pod that served the request.

Today the `probe` Service has no `trafficDistribution`, and no `DestinationRule` exists. The requests of `shuttle` are spread over both probes.

## Your task

1. Make the `probe` Service prefer endpoints that are close to the client, with the Kubernetes `Service` field for it. Keep its selector and port as they are.
2. Create a `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe` with outlier detection, so that a failing endpoint can be ejected: `consecutive5xxErrors` is `2`, `interval` is `5s`, `baseEjectionTime` is `30s` and `maxEjectionPercent` is `100`.
3. Prove that 20 requests from `shuttle` to `http://probe:8000/hostname` are all answered by `probe-zone-a`.

## Rules

- The preference must come from the `Service`. Do not set `localityLbSetting` (including `distribute` and `failover`) in the `DestinationRule`, and create no second `DestinationRule`.
- Do not change the node's labels, the localities of the pods, or the `shuttle` Deployment.
- Do not scale, add or remove Deployments. `probe-zone-b` must stay a healthy endpoint of the Service.

## Useful commands

```sh
kubectl get service probe -n starfleet -o jsonpath='{.spec.trafficDistribution}{"\n"}'
```

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```
