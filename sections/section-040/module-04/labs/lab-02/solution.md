# Solution: Give Every Ship Its Orbit

The `DestinationRule` was correct all along. `probe-zone-b` had lost its `istio-locality` label, so it took the node's orbit, `local/zone-a`. The shuttle saw two "nearby" probes and split its signals between them.

## Step 1: Find the ship in the wrong orbit

Send 20 signals from the shuttle:

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

You should see a mix, for example:

```text
   6 probe-zone-a
  14 probe-zone-b
```

The preference is active, yet both probes answer. Ask the shuttle's proxy which locality each probe endpoint has:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"address"'
```

```text
                "address": {
                        "address": "10.244.0.7",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.9",
                    "zone": "zone-a"
```

Both endpoints are in `zone-a`. Find out which pod is in the wrong orbit:

```sh
kubectl get pods -n starfleet -l app=probe -L istio-locality,topology.kubernetes.io/zone
```

```text
NAME                            READY   STATUS    RESTARTS   AGE     ISTIO-LOCALITY   ZONE
probe-zone-a-846b7b8d66-49drg   2/2     Running   0          4m12s   local.zone-a     zone-a
probe-zone-b-857f449bf8-8sbns   2/2     Running   0          4m4s                     zone-a
```

`probe-zone-b` has no `istio-locality` label, so it inherits the node's zone, `zone-a`.

## Step 2: Give the ship its orbit

Put the label back on the **pod template**. The value uses a dot, because a label value cannot contain a slash:

```sh
kubectl -n starfleet patch deployment probe-zone-b --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"local.zone-b"}}}}}'
kubectl -n starfleet rollout status deployment probe-zone-b
```

You should see (trimmed to the first and last line):

```text
deployment.apps/probe-zone-b patched
deployment "probe-zone-b" successfully rolled out
```

Changing the pod template starts a new pod, and Istio reads the locality when the pod starts.

## Step 3: Check the orbits again

```sh
kubectl get pods -n starfleet -l app=probe -L istio-locality
```

```text
NAME                            READY   STATUS    RESTARTS   AGE     ISTIO-LOCALITY
probe-zone-a-846b7b8d66-49drg   2/2     Running   0          4m34s   local.zone-a
probe-zone-b-56b7474bd-jj75c    2/2     Running   0          13s     local.zone-b
```

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"address"'
```

```text
                "address": {
                        "address": "10.244.0.7",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.10",
                    "zone": "zone-b"
```

One probe in each orbit.

## Step 4: Prove the signals stay close

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

```text
  20 probe-zone-a
```

Every signal stays in the shuttle's own orbit. `probe-zone-b` is now a fallback, used only when `zone-a` has no healthy probe left.

## Common mistakes

- **Putting the label on the Deployment's own `metadata`.** Only labels on the pod template reach the pods.
- **Writing `local/zone-b`.** Kubernetes rejects a slash in a label value. Use `local.zone-b`.
- **Relabelling the node.** The node holds the shuttle and both probes, so moving it moves every ship together.
- **Adding `distribute` to the `DestinationRule`.** Fixed weights hide the problem instead of fixing the ship's orbit.
