# Question

Solve this question on: `terminal`

The probe in `zone-b` has received no traffic for weeks, and the team wants proof that the path to it still works before they ever need it.

The namespace `starfleet` runs on a cluster with one node. The node has the labels region `local` and zone `zone-a`. Three Deployments run there:

| Deployment | Locality |
| --- | --- |
| `shuttle` | `local/zone-a`, the node's locality. You send every test request from here |
| `probe-zone-a` | `local/zone-a` |
| `probe-zone-b` | `local/zone-b` |

A **locality** is the region, zone and subzone a pod runs in. Both probe Deployments sit behind the `probe` Service on port `8000`. Its `/hostname` path returns the name of the pod that served the request.

Today the `probe` `DestinationRule` has `outlierDetection` and `localityLbSetting: {enabled: true}`. So the sidecar proxy of `shuttle` sends every request to `zone-a`, and `probe-zone-b` receives none. The path to `zone-b` must be in use all the time, so the team knows it works before it is needed.

## Your task

Change the `probe` `DestinationRule` so that requests sent from `local/zone-a`, any subzone, are split:

- **80** to `local/zone-a`, any subzone
- **20** to `local/zone-b`, any subzone

Then prove it: out of 100 requests from `shuttle`, about 80 reach `probe-zone-a` and about 20 reach `probe-zone-b`.

## Rules

- Keep the name `probe` for the `DestinationRule`, and do not create a second one.
- Do not change the Deployments, their labels or the `probe` Service.

## Useful command

```sh
for i in $(seq 1 100); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```
