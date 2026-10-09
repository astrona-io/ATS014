# Question

Solve this question on: `terminal`

The `shuttle` should only talk to the probe in its own zone, but one probe has lost track of where it runs.

The namespace `starfleet` runs on a cluster with one node. The node has the labels region `local` and zone `zone-a`. Three Deployments run there:

| Deployment | Meant to run in locality |
| --- | --- |
| `shuttle` | the node's locality, `local/zone-a`. You send every test request from here |
| `probe-zone-a` | `local/zone-a` |
| `probe-zone-b` | `local/zone-b` |

A **locality** is the region and zone a pod runs in. Istio takes it from the node's `topology.kubernetes.io/region` and `topology.kubernetes.io/zone` labels, unless the pod template sets its own with the `istio-locality` label (format `region.zone`, with a dot).

Both probe Deployments sit behind the `probe` Service on port `8000`. Its `/hostname` path returns the name of the pod that served the request.

The `probe` `DestinationRule` is correct. It has `outlierDetection` and `localityLbSetting: {enabled: true}`, so the sidecar proxy of `shuttle` should send every request to its own zone, `zone-a`. Instead, its requests go to both probes.

## Your task

1. Find out, from the endpoint list of the `shuttle` proxy, which locality each probe endpoint has.
2. Give the probe that runs in the wrong locality the locality it is meant to run in.
3. Prove that 20 requests from `shuttle` all reach `probe-zone-a`.

## Rules

- Do not change the node's labels, the `shuttle` Deployment, the `probe-zone-a` Deployment, the `probe` Service or the `probe` `DestinationRule`.
- Do not add or remove Deployments.
- The cluster has a single node, so the fix belongs on the probe pod itself.

## Useful commands

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"address"'
```

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```
