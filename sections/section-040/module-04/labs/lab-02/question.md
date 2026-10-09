# Give Every Ship Its Orbit

Astronaut, the planet `starfleet` has one node, labelled region `local` and zone `zone-a`. Three ships fly there:

| Ship | Meant to fly in |
| --- | --- |
| `shuttle` | the node's orbit, `local/zone-a`. You send every signal from here |
| `probe-zone-a` | `local/zone-a` |
| `probe-zone-b` | `local/zone-b` |

Both probes answer to the `probe` beacon on port `8000`. Its `/hostname` path answers with the name of the pod that served the signal.

The `probe` `DestinationRule` is correct. It has `outlierDetection` and `localityLbSetting: {enabled: true}`, so the shuttle should keep every signal in its own orbit, `zone-a`. Instead, its signals land on both probes.

## Your task

1. Find out, from the shuttle's endpoint list, which locality each probe endpoint has.
2. Put the ship that sits in the wrong orbit into the orbit it is meant to fly in.
3. Prove that 20 signals from the shuttle all reach `probe-zone-a`.

## Rules

- Do not change the node's labels, the `shuttle`, `probe-zone-a`, the `probe` Service or the `probe` `DestinationRule`.
- Do not add or remove ships.
- The cluster has a single node, so the fix belongs on the ship itself.

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
