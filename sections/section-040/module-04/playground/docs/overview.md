# Overview: Locality Load Balancing And Failover (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It starts a fresh cluster,
installs Istio, the shuttle and the probe in two orbits, and then waits. There is no task, no
`astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it. The node is labelled
  with region `local` and zone `zone-a`.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only). `istiod` is mission control:
  it sends every proxy its orders.
- Mesh-wide **access logs**: every proxy writes one line per signal, the ship's flight log.
- Namespace **`starfleet`** (the planet you work on), with sidecar injection:
  - **`shuttle`**, your client. It flies in the node's orbit, `local/zone-a`.
  - **`probe-zone-a`** and **`probe-zone-b`**: the echo probe in two orbits, behind one `probe`
    Service on port `8000`. Each declares its orbit with the `istio-locality` pod label.
    `/hostname` answers with the pod's name.
  - **`probe-zone-a-damaged`**: a ship in `local/zone-a` that answers `503` to every signal but stays
    ready. It starts at 0 replicas.
- **No `DestinationRule`.** Writing one is the point of the module.

## Helpers

Paste these once in each new terminal:

```sh
count_orbits() { for i in $(seq 1 ${1:-20}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]' || echo failed
done | sort | uniq -c; }
status_codes() { kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname; done; echo'; }
```

## Things to try

Each idea below is a small change to the files you made while reading the module. Edit your saved
`DestinationRule`, apply it with `kubectl apply -f`, and watch what happens.

- Run `count_orbits 20` with no `DestinationRule`. Then add only `localityLbSetting: {enabled: true}`
  and run it again. Then add `outlierDetection`. Only the last one keeps every signal in `zone-a`.
- In the `distribute` file, try 50/50 and 90/10, and measure each with `count_orbits 100`.
- Lower `maxEjectionPercent` to `10` in the failover `DestinationRule`, launch the damaged ship, and
  see whether the signals still leave `zone-a`.
- Scale `probe-zone-a` to 0 and compare it with launching the damaged ship: one is endpoint removal,
  the other is endpoint failure.
- Run `istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000||probe.starfleet.svc.cluster.local"`
  while the damaged ship is up, and watch its `OUTLIER CHECK` column.

## Start over

Remove your `DestinationRule` and put the ships back:

```sh
kubectl delete destinationrule probe -n starfleet
kubectl -n starfleet scale deployment probe-zone-a-damaged --replicas=0
kubectl -n starfleet scale deployment probe-zone-a --replicas=1
```

## When you're done

```sh
astrona destroy ats-014-playground-040-04
```

(`astrona destroy` takes the environment name, not the configuration path.)
