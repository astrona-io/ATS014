# Solution Walkthrough

One pod took every request because the `probe` `DestinationRule` hashes the client's IP address. The fix is one field: replace the hash with an algorithm that takes the pods in turn.

---

## Step 1: See the problem

Send 8 requests from the `shuttle` pod and count which probe pod answered:

```sh
for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o '"probe-[^"]*"'
done | sort | uniq -c
```

```text
   8 "probe-v1-7888d6c6d5-6zlch"
```

All 8 requests landed on one pod, although the Service has four.

## Step 2: Find the cause

A `DestinationRule` is the Istio object that holds policies for traffic to one host, including the load balancer. Read the one for `probe`:

```sh
kubectl get destinationrule probe -n starfleet -o yaml
```

The part that matters (shortened):

```text
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      consistentHash:
        useSourceIp: true
```

`consistentHash` with `useSourceIp: true` makes the sending proxy calculate a hash from the client's IP address and pick the pod from that hash. Every request from the `shuttle` pod comes from the same address, so it always hashes to the same pod.

Envoy stores the endpoints of one destination as a **cluster**, and it stores the algorithm as the cluster field `lbPolicy`. The `shuttle` pod's proxy confirms the cause:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json \
  | grep -E '"lbPolicy"|ringHash'
```

```text
        "lbPolicy": "RING_HASH",
        "ringHashLbConfig": {
```

`RING_HASH` is Envoy's name for consistent hashing.

## Step 3: Spread the requests in turn

Replace the hash with round robin. Save this as `destinationrule-probe.yaml`:

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
      simple: ROUND_ROBIN
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

## Step 4: Prove it

Count the `lbPolicy` lines the `shuttle` pod's proxy now holds for the probe:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json \
  | grep -c '"lbPolicy"'
```

```text
0
```

There is no `lbPolicy` line at all. Round robin is Envoy's own default, and the dump leaves default values out. `RING_HASH` is gone. Now send 8 requests again:

```sh
for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o '"probe-[^"]*"'
done | sort | uniq -c
```

One run gave:

```text
   2 "probe-v1-7888d6c6d5-6zlch"
   1 "probe-v1-7888d6c6d5-t68zd"
   3 "probe-v1-7888d6c6d5-w69gh"
   2 "probe-v2-58767cc46-znght"
```

All four pods answered. The spread is roughly even rather than exactly 2, 2, 2, 2. The proxy runs more than one worker thread, and each thread keeps its own turn order.

Send it for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-03
```

```text
PASS: the probe DestinationRule uses simple ROUND_ROBIN with no consistentHash, the shuttle's proxy holds a round robin cluster, and 16 live signals reached all 4 probe pods (most on one pod: 4)
```

---

## Mistakes that fail the grader

- **Adding `simple` next to `consistentHash`.** Istio rejects a `loadBalancer` that has both.
- **Choosing `RANDOM` or `LEAST_REQUEST`.** They spread requests too, but the task asks for round robin.
- **Scaling the Deployments.** More or fewer pods do not change how the proxy picks one. Keep `probe-v1` at 3 and `probe-v2` at 1.
- **Submitting straight after `kubectl apply`.** `istiod`, Istio's control plane, needs a moment to send the new configuration to the proxy. If the grader still sees `RING_HASH`, wait a few seconds and submit again.
