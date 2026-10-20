# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The Start section finds the cause: one field in the `DestinationRule` sends every request from the `shuttle` pod to one probe pod. Items 1 and 2 are the fix. Items 3 to 5 prove the result.

---

## Start: See The Problem And Find The Cause

The task says that every request from the `shuttle` pod lands on the same pod. Send 8 requests from `shuttle` to the `probe` Service, and count which probe pod answered. The path `/hostname` returns the name of the pod that served the request. The lab ships this loop as the resource `count-pods.sh`, so you can also run `astrona res run count-pods.sh 8`:

```sh
for i in $(seq 1 8); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o '"probe-[^"]*"'
done | sort | uniq -c
```

```text
   8 "probe-v1-7888d6c6d5-b2rxl"
```

All 8 requests landed on one pod, although the Service has four. A `DestinationRule` is the Istio object that holds policies for traffic to one host, including the load balancing policy. Read the one for `probe`, and read the load balancing algorithm that the proxy of `shuttle` uses. The proxy is the Envoy container that Istio adds to each pod. Envoy keeps the endpoints of one destination in a cluster, and `lbPolicy` is the algorithm of that cluster:

```sh
kubectl -n starfleet get destinationrule probe -o yaml | sed -n '/^spec:/,$p'
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local -o json | grep -E '"lbPolicy"|ringHash'
```

```text
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      consistentHash:
        useSourceIp: true
        "lbPolicy": "RING_HASH",
        "ringHashLbConfig": {
```

`consistentHash` with `useSourceIp: true` makes the sending proxy calculate a hash from the client IP address and pick the pod from that hash. Every request from the `shuttle` pod comes from the same address, so it always hashes to the same pod. `RING_HASH` is Envoy's name for consistent hashing, and the proxy confirms it.

Before you fix it, save the identity of the workloads. Item 5 compares against it:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME       REPLICAS   UID
probe-v1   3          30e64f18-ab32-4f7a-89f5-4a580b0d5c92
probe-v2   1          272339d3-6be0-4ac5-bc3a-f04491bc1bdc
shuttle    1          85ca61c6-3199-4cc5-9e12-5b7e3593ef6e
{"app":"probe"} 8000
```

---

## Items 1 And 2: Replace The Hash With Round Robin

> **Task item 1:** The `DestinationRule` named `probe` in `starfleet` (host `probe`) uses **`simple: ROUND_ROBIN`** as its host-level `trafficPolicy.loadBalancer`.
>
> **Task item 2:** The `DestinationRule` contains **no `consistentHash`** anywhere.

Both items need one change. A `loadBalancer` holds one algorithm, so you replace `consistentHash` with `simple: ROUND_ROBIN`. Istio rejects a `loadBalancer` that has both. Save this as `destinationrule-probe.yaml`:

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

Check item 1. Print the host-level load balancer:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer}{"\n"}'
```

```text
{"simple":"ROUND_ROBIN"}
```

Check item 2. Count the lines with `consistentHash` in the whole object:

```sh
kubectl -n starfleet get destinationrule probe -o yaml | grep -c consistentHash
```

```text
0
```

The count is `0`, so `consistentHash` is gone.

---

## Item 3: The Proxy Holds A Round Robin Cluster

> **Task item 3:** The `shuttle` pod's proxy holds a round robin cluster for `probe` (check it with `istioctl proxy-config cluster`).

`istiod`, the Istio control plane, sends the new configuration to every proxy. Wait a few seconds. Then count the lines with `lbPolicy` and with `RING_HASH` in the cluster of `probe`:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local -o json | grep -c '"lbPolicy"'
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local -o json | grep -c RING_HASH
```

```text
0
0
```

There is no `lbPolicy` line at all, and `RING_HASH` is gone. Round robin is the default of Envoy, and the dump leaves default values out. So a cluster without an `lbPolicy` line is a round robin cluster. If `RING_HASH` is still there, `istiod` has not sent the change yet. Wait a few seconds and run the commands again.

---

## Item 4: All Four Pods Answer

> **Task item 4:** 16 requests from the `shuttle` pod to `http://probe:8000/hostname` reach **all four** probe pods, and no pod answers more than 8 of them.

Send 16 requests, and count the pods:

```sh
for i in $(seq 1 16); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o '"probe-[^"]*"'
done | sort | uniq -c
```

```text
   4 "probe-v1-7888d6c6d5-b2rxl"
   4 "probe-v1-7888d6c6d5-gd9qc"
   4 "probe-v1-7888d6c6d5-kcml4"
   4 "probe-v2-58767cc46-2d5kr"
```

All four pods answered, four requests each. Your run may be less even, for example 5, 4, 4 and 3. The proxy runs more than one worker thread, and each thread keeps its own turn order. That is why the task accepts up to 8 requests for one pod.

---

## Item 5: The Workloads Are Unchanged

> **Task item 5:** The workloads stay as they are: `probe-v1` keeps 3 replicas, `probe-v2` keeps 1, no Deployment is added or removed, and the `probe` Service keeps selecting `app: probe`.

Run the two commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME       REPLICAS   UID
probe-v1   3          30e64f18-ab32-4f7a-89f5-4a580b0d5c92
probe-v2   1          272339d3-6be0-4ac5-bc3a-f04491bc1bdc
shuttle    1          85ca61c6-3199-4cc5-9e12-5b7e3593ef6e
{"app":"probe"} 8000
```

The output is the same as before. `probe-v1` has 3 replicas, `probe-v2` has 1, and the Service still selects `app: probe`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-03
```

The grader reads the `DestinationRule`, reads the proxy of `shuttle`, and sends live requests.

---

## Mistakes That Fail The Grader

- **Adding `simple` next to `consistentHash` (items 1 and 2).** Istio rejects a `loadBalancer` that has both.
- **Choosing `RANDOM` or `LEAST_REQUEST` (item 1).** They spread requests too, but the task asks for round robin.
- **Scaling the Deployments (item 5).** More or fewer pods do not change how the proxy picks one. Keep `probe-v1` at 3 and `probe-v2` at 1.
- **Submitting straight after `kubectl apply` (item 3).** `istiod` needs a moment to send the new configuration to the proxy. If the grader still sees `RING_HASH`, wait a few seconds and submit again.
