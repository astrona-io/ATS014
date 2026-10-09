# Solution Walkthrough

The `VirtualService` is correct. The `DestinationRule` gives the `v2` subset a label that no pod has, so the mirror cluster has no endpoints and the proxy has nowhere to send the copies. The client never notices, because the route to `v1` still works.

---

## Step 1: Paste the helpers

These shell helpers count which version **sent the response** and which versions **received** each request. `mark_start` saves the current time, `send_requests` sends requests from `shuttle`, and `count_received` counts the requests each version received since the saved time, from its application log:

```sh
mark_start() { START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$START_TIME | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

## Step 2: See that v2 receives nothing

```sh
mark_start; send_requests 5; count_received
```

```text
   5 probe-v1
probe-v1 received: 5
probe-v2 received: 0
```

Every response comes from v1, as it should. But v2 received nothing, although the `VirtualService` mirrors every request to it.

## Step 3: Run `istioctl analyze`

`istioctl analyze` checks the Istio objects in a namespace and reports problems it finds:

```sh
istioctl analyze -n starfleet
```

You should see (shortened to the error):

```text
Error [IST0173] (DestinationRule starfleet/probe) The Subset v2 defined in the DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).
```

`IST0173` points at the `DestinationRule`: the `v2` subset selects no pods.

## Step 4: Confirm it in the proxy of shuttle

The sidecar proxy of the client sends the copies, so check its configuration. First, the mirror policy is there:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet -o json | grep -i -A3 requestMirrorPolicies
```

You should see (shortened):

```text
"requestMirrorPolicies": [
    {
        "cluster": "outbound|8000|v2|probe.starfleet.svc.cluster.local",
        "runtimeFraction": {
```

But the mirror cluster has no endpoints (pod addresses):

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
```

The proxy is configured to send copies, but the destination is empty.

## Step 5: Compare the labels

Look at the labels the `probe` pods carry, and at the labels each subset asks for:

```sh
kubectl get pods -n starfleet -l app=probe --show-labels
kubectl get destinationrule probe -n starfleet -o jsonpath='{range .spec.subsets[*]}{.name}{" -> version="}{.labels.version}{"\n"}{end}'
```

You should see (the pod list shortened to names and the `version` label):

```text
probe-v1-7888d6c6d5-srnzp   ...,version=v1
probe-v2-58767cc46-vsd7j    ...,version=v2
v1 -> version=v1
v2 -> version=canary
```

The `probe-v2` pod carries `version=v2`, but the `v2` subset asks for `version=canary`.

## Step 6: Fix the DestinationRule

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

## Step 7: Prove that v2 receives every copy

Check the mirror cluster again. It now has an endpoint:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:8080     HEALTHY     OK                outbound|8000|v2|probe.starfleet.svc.cluster.local
```

Then count both sides again:

```sh
mark_start; send_requests 5; count_received
```

```text
   5 probe-v1
probe-v1 received: 5
probe-v2 received: 5
```

Every response still comes from v1, and v2 now receives a copy of every request. `istioctl analyze -n starfleet` reports no issues again. Submit:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-02
```

```text
PASS: subsets v1 and v2 select their probe pods, the VirtualService still routes to v1 and mirrors 100% to v2, the mirror cluster has endpoints, all 30 responses to the client came from probe-v1, and probe-v2 received 20 copies of 20 requests
```

---

## Mistakes that fail the grader

- **Changing the `VirtualService` instead of the `DestinationRule`.** Routing to v2, or removing the mirror, breaks requirement 3 or 4.
- **Changing the pod labels.** If you give the `probe-v2` pods the label `version: canary`, the subset selects them, but the grader requires the pods to stay unchanged.
- **Lowering `mirrorPercentage`.** The mirror must copy every request.
- **Checking only the client.** The client got correct responses before the fix, too. The proof is the endpoints of the mirror cluster and the copies arriving at v2.
