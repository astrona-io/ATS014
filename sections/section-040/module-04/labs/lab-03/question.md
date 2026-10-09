# Split Signals Between Two Orbits

Astronaut, the planet `starfleet` has one node, labelled region `local` and zone `zone-a`. Three ships fly there:

| Ship | Orbit |
| --- | --- |
| `shuttle` | `local/zone-a`, the node's orbit. You send every signal from here |
| `probe-zone-a` | `local/zone-a` |
| `probe-zone-b` | `local/zone-b` |

Both probes answer to the `probe` beacon on port `8000`. Its `/hostname` path answers with the name of the pod that served the signal.

Today the `probe` `DestinationRule` has `outlierDetection` and `localityLbSetting: {enabled: true}`, so every signal from the shuttle stays in `zone-a`. Mission control wants the path to `zone-b` in use all the time, so it is known to work before it is needed.

## Your task

Change the `probe` `DestinationRule` so that signals sent from `local/zone-a`, any subzone, are split:

- **80** to `local/zone-a`, any subzone
- **20** to `local/zone-b`, any subzone

Then prove it: out of 100 signals from the shuttle, about 80 reach `probe-zone-a` and about 20 reach `probe-zone-b`.

## Rules

- Keep the name `probe` for the `DestinationRule`, and do not create a second one.
- Do not change the ships, their labels or the `probe` Service.

## Useful command

```sh
for i in $(seq 1 100); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```
