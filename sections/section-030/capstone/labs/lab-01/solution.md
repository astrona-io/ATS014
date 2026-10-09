# Solution Walkthrough

You need two objects. The `DestinationRule` (the Istio object that holds policies for traffic to one host) carries a policy at two levels. The `VirtualService` (the Istio object that holds routing rules) carries two features on one rule: a route and a mirror. Neither half tells you whether the other worked, so you check four separate things.

---

## Step 1: Read the Starting State

```sh
kubectl -n sessions get pods -o wide --show-labels | head
kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | wc -l
```

```text
httpbin-canary-...-lq2wn   2/2   Running   10.244.0.16   app=httpbin,version=canary
httpbin-canary-...-x8plm   2/2   Running   10.244.0.17   app=httpbin,version=canary
httpbin-stable-...-2knzp   2/2   Running   10.244.0.11   app=httpbin,version=stable
httpbin-stable-...-7wqrt   2/2   Running   10.244.0.12   app=httpbin,version=stable
httpbin-stable-...-m4xvd   2/2   Running   10.244.0.13   app=httpbin,version=stable
0
```

Write down the two canary IP addresses. The grader checks that no caller response comes from them, and so should you. The `0` on the last line is the number of lines in the canary pods' proxy access logs before you start.

---

## Step 2: The DestinationRule, Policy at Two Levels

Write the manifest to a file and apply the file. In the exam, a file lets you read, edit and apply the configuration again.

Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: sessions
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-session
  subsets:
    - name: stable
      labels:
        version: stable
    - name: canary
      labels:
        version: canary
      trafficPolicy:
        loadBalancer:
          simple: LEAST_REQUEST
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

The host-level `consistentHash` makes the sending proxy pick the pod from a hash of the `x-session` header, so the same session always reaches the same pod. The `stable` subset has **no** `trafficPolicy` on purpose. Every field a subset policy sets *replaces* the host's whole field for that subset. A `loadBalancer` on `stable` would therefore have to repeat the consistent hashing, and the grader requires that `stable` inherits it instead.

---

## Step 3: One Rule, Two Features

Save this as `virtualservice-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: sessions
spec:
  hosts:
    - httpbin
  http:
    - route:
        - destination:
            host: httpbin
            subset: stable
      mirror:
        host: httpbin
        subset: canary
      mirrorPercentage:
        value: 100.0
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

Then check the result:

```sh
istioctl analyze -n sessions
```

```text
✔ No validation issues found when analyzing namespace: sessions.
```

`mirror` and `mirrorPercentage` sit next to `route` in the same rule. If you add `canary` as a second entry in `route`, it becomes a weighted destination, callers start reaching canary pods, and the grader fails check 10.

---

## Step 4: Confirm the Clusters Differ

```sh
istioctl proxy-config cluster deploy/tester -n sessions \
  --fqdn httpbin.sessions.svc.cluster.local -o json | grep -E '"name"|lbPolicy'
```

```text
"name": "outbound|8000||httpbin.sessions.svc.cluster.local",
"lbPolicy": "RING_HASH",
"name": "outbound|8000|canary|httpbin.sessions.svc.cluster.local",
"lbPolicy": "LEAST_REQUEST",
"name": "outbound|8000|stable|httpbin.sessions.svc.cluster.local",
"lbPolicy": "RING_HASH",
```

Envoy stores the endpoints of one destination as a **cluster**, and `lbPolicy` is the algorithm of that cluster. `stable` inherited `RING_HASH`, Envoy's name for `consistentHash`. `canary` shows `LEAST_REQUEST` from its own policy. The proxy sends the mirrored copy to the **canary cluster**, so `LEAST_REQUEST` decides which canary pod receives each copy. The caller's session affinity has no effect on it.

---

## Step 5: Verify Affinity, And That Callers Never See Canary

```sh
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-session: alice"; done'
kubectl -n sessions logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.12:8080
```

All twelve requests reached one endpoint, and `10.244.0.12` is a **stable** pod. Neither canary IP address appears. The mirrored copy does not show up in the upstream field of the caller's access log, because for the caller the request went to `stable`.

Then the fallback case:

```sh
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
kubectl -n sessions logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
   5 10.244.0.11:8080
   4 10.244.0.12:8080
   3 10.244.0.13:8080
```

The requests spread over the three stable endpoints. The policy is unchanged; these requests have nothing to hash, so the proxy uses normal load balancing.

---

## Step 6: Prove the Canary Is Receiving Copies

No caller traffic is routed to the canary, so every request in the canary pods' proxy access logs is a mirrored copy. In Istio 1.30.5 the mirrored copy no longer gets a `-shadow` suffix on its `Host` header, so you cannot search for that suffix. Count the `GET /get` lines instead. The access log keeps growing across attempts, so take a count before and after:

```sh
BEFORE=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c 'GET /get')
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -H "x-session: alice" http://httpbin:8000/get; done'
sleep 3
AFTER=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c 'GET /get')
echo "mirrored: $((AFTER - BEFORE)) of 40"
```

```text
mirrored: 40 of 40
```

You should see a number at or close to 40. The grader accepts 30 or more. Look at the last line of each canary pod's log to see what a copy looks like:

```sh
kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=1
```

```text
[2026-10-09T20:59:57.397Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 733 0 0 "10.244.0.13" "curl/8.22.0" "4bac2d12-7f1a-91ef-a74d-00863b4f8ff3" "httpbin:8000" "10.244.0.9:8080" inbound|8080|| 127.0.0.6:32919 10.244.0.9:8080 10.244.0.13:0 outbound_.8000_.canary_.httpbin.sessions.svc.cluster.local default
[2026-10-09T20:59:57.401Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 733 0 0 "10.244.0.13" "curl/8.22.0" "eb31073e-20b0-9340-9265-c9316026d684" "httpbin:8000" "10.244.0.12:8080" inbound|8080|| 127.0.0.6:45645 10.244.0.12:8080 10.244.0.13:0 outbound_.8000_.canary_.httpbin.sessions.svc.cluster.local default
```

Each line names its canary pod as the upstream (`10.244.0.9:8080` and `10.244.0.12:8080`), and the request came from the `tester` pod (`10.244.0.13`) through its `canary` cluster. The authority is the plain `httpbin:8000`, with no `-shadow` suffix. Both canary pods appear, because `LEAST_REQUEST` spreads the copies, as the task asks. In this run the two pods received 18 and 22 of the 40 copies.

The grader also checks that the `tester` pod's proxy holds the mirror in its routes:

```sh
istioctl proxy-config routes deploy/tester -n sessions -o json | grep -c requestMirrorPolicies
```

```text
2
```

Any number above `0` means the mirror reached the sidecar proxy. Here the count is `2`: the `tester` proxy holds the mirror for the `httpbin` host in two route tables, named `80` and `8000`.

When all checks look right, send the lab for grading:

```sh
astrona submit -c sections/section-030/capstone/labs/lab-01
```

---

## Common Mistakes

- **Canary added as a route destination.** It becomes a weighted split and callers reach it. This is the failure the specification calls out explicitly.
- **Giving `stable` its own `trafficPolicy`.** The task requires that `stable` inherits the host policy.
- **Putting `consistentHash` inside the `stable` subset instead of at host level.** The behaviour can look right, but the grader still fails it.
- **Expecting the caller's session affinity to control the mirrored copy.** The copy goes to the canary cluster and follows *that* cluster's policy.
- **Testing affinity without a baseline of which pods are which.** Record the stable and canary IPs first.
- **Counting canary log lines without a `BEFORE` count.** The log keeps growing across attempts.
- **Leaving out `mirrorPercentage`.** The default is 100%, but the task asks for it explicitly, and the grader checks it.
