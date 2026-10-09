# Solution: Split Traffic Between Two Zones With Distribute

The starting `DestinationRule` switches the locality preference on, so the sidecar proxy of `shuttle` sends every request to `zone-a`. A fixed split needs `distribute` instead: it sets exact weights for requests that start in a given locality.

## Step 1: Look at the starting state

```sh
kubectl -n starfleet get destinationrule
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

You should see:

```text
NAME    HOST    AGE
probe   probe   10s
  20 probe-zone-a
```

`probe-zone-b` gets no requests at all.

## Step 2: Replace the preference with a fixed split

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      localityLbSetting:
        enabled: true
        distribute:
        - from: local/zone-a/*
          to:
            "local/zone-a/*": 80
            "local/zone-b/*": 20
```

- `from: local/zone-a/*` matches the locality of `shuttle`: region `local`, zone `zone-a`, any subzone.
- The two weights add up to exactly 100. Istio rejects any other total.
- `distribute` does not need `outlierDetection`, so this file leaves it out. Keeping it would also work.

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

## Step 3: Prove the split

Send 100 requests:

```sh
for i in $(seq 1 100); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

You should see something like:

```text
  80 probe-zone-a
  20 probe-zone-b
```

The proxy picks a zone by weight for each request, so a few requests of difference from run to run are normal.

## Common mistakes

- **Weights that do not add up to 100.** Istio rejects the object with `total locality weight ... != 100`.
- **Writing the localities with dots.** Dots are only for the `istio-locality` pod label. In a `DestinationRule`, use slashes: `local/zone-a/*`.
- **Adding `failover` as well.** `distribute` and `failover` cannot be combined for one host.
- **A `from` that does not match `shuttle`.** A client whose locality matches no `from` keeps the normal behaviour, so nothing changes.
