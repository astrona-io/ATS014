# Solution Walkthrough

The flight plan is correct. The docking instructions point the `v2` ship class at a label no ship carries, so the mirror has nowhere to send its copies. The sender never notices.

---

## Step 1: Paste the helpers

These count which version **answered** and which versions **received** each signal:

```sh
mark_start() { M=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$M | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

## Step 2: See the quiet shadow

```sh
mark_start; send_requests 5; count_received
```

```text
   5 probe-v1
probe-v1 received: 5
probe-v2 received: 0
```

Every answer comes from v1, as it should. But v2 received nothing, although the flight plan mirrors every signal to it.

## Step 3: Ask `istioctl analyze`

```sh
istioctl analyze -n starfleet
```

You should see (trimmed to the error):

```text
Error [IST0173] (DestinationRule starfleet/probe) The Subset v2 defined in the DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).
```

`IST0173` points straight at the docking instructions: the `v2` subset selects no pods.

## Step 4: Confirm it in the shuttle's proxy

The mirror policy is there:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet -o json | grep -i -A3 requestMirrorPolicies
```

You should see (trimmed):

```text
"requestMirrorPolicies": [
    {
        "cluster": "outbound|8000|v2|probe.starfleet.svc.cluster.local",
        "runtimeFraction": {
```

But the mirror cluster holds no ships:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
```

The order to send copies exists. The destination is empty.

## Step 5: Compare the labels

Look at what the probe ships carry, and what the subsets ask for:

```sh
kubectl get pods -n starfleet -l app=probe --show-labels
kubectl get destinationrule probe -n starfleet -o jsonpath='{range .spec.subsets[*]}{.name}{" -> version="}{.labels.version}{"\n"}{end}'
```

You should see (the pod list trimmed to names and the `version` label):

```text
probe-v1-7888d6c6d5-srnzp   ...,version=v1
probe-v2-58767cc46-vsd7j    ...,version=v2
v1 -> version=v1
v2 -> version=canary
```

The `v2` ship carries `version=v2`, but the `v2` subset asks for `version=canary`.

## Step 6: Fix the docking instructions

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

## Step 7: Prove the shadow hears every signal

The mirror cluster now has a ship:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:8080     HEALTHY     OK                outbound|8000|v2|probe.starfleet.svc.cluster.local
```

And the copies arrive:

```sh
mark_start; send_requests 5; count_received
```

```text
   5 probe-v1
probe-v1 received: 5
probe-v2 received: 5
```

Every answer still comes from v1, and v2 now receives a copy of every signal. `istioctl analyze -n starfleet` is clean again. Submit:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-02
```

```text
PASS: subsets v1 and v2 select their probe pods, the flight plan still routes to v1 and mirrors 100% to v2, the mirror cluster has ships, all 30 sender answers came from probe-v1, and the shadow received 20 copies of 20 signals
```

---

## Mistakes that fail the grader

- **Changing the flight plan instead of the docking instructions.** Routing to v2, or removing the mirror, breaks requirement 3 or 4.
- **Relabelling the ships.** Changing the `probe-v2` pods to `version: canary` "fixes" the subset, but the grader requires the pods to stay unchanged.
- **Lowering `mirrorPercentage`.** The mirror must copy every signal.
- **Checking only the sender.** The sender was happy before the fix, too. The proof is the mirror cluster's endpoints and the copies arriving at v2.
