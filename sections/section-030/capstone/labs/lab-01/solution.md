# Solution Walkthrough

Mission debrief, astronaut. Two objects again, but this time the `DestinationRule` carries policy at two levels and the `VirtualService` carries two features on one rule. Neither half tells you whether the other worked, so the verification is in four independent pieces.

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

Write down the two canary IPs — the grader checks no caller response comes from them, and so should you.

---

## Step 2: The DestinationRule, Policy at Two Levels

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-httpbin.yaml <<'EOF'
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
EOF
kubectl apply -f destinationrule-httpbin.yaml
```

The `stable` subset deliberately has **no** `trafficPolicy`. That is not laziness — a subset policy *replaces* the host-level one for that subset, so giving `stable` its own would mean restating the consistent hashing there and would silently drop anything else the host policy ever grows.

---

## Step 3: One Rule, Two Features

```sh
cat > virtualservice-httpbin.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-httpbin.yaml
istioctl analyze -n sessions
```

```text
✔ No validation issues found when analyzing namespace: sessions.
```

`mirror` and `mirrorPercentage` are siblings of `route`. Adding `canary` as a second entry in `route` would make it a weighted destination, callers would start reaching canary pods, and the grader fails you on check 10.

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

`stable` inherited `RING_HASH`; `canary` shows `LEAST_REQUEST` from its own policy. Note that the mirrored copy is dispatched to the **canary cluster**, so it is `LEAST_REQUEST` that decides which canary pod receives each copy — the caller's affinity has no bearing on it.

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

One endpoint, twelve times, and `10.244.0.12` is a **stable** pod. Neither canary IP appears — mirrored traffic does not show up in the caller's own upstream field, because from the caller's point of view the request went to `stable`.

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

Three stable endpoints. The policy is unchanged; these requests just have nothing to hash.

---

## Step 6: Prove the Canary Is Receiving Copies

Baseline, send traffic, measure the delta:

```sh
BEFORE=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c -- -shadow)
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -H "x-session: alice" http://httpbin:8000/get; done'
sleep 3
AFTER=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c -- -shadow)
echo "mirrored: $((AFTER - BEFORE)) of 40"
kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=2 | grep -i shadow
```

```text
mirrored: 40 of 40
[2026-09-27T15:11:04.552Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 512 2 1 "-" "curl/8.5.0" "..." "httpbin-shadow" "10.244.0.17:8080" ...
```

Forty of forty, carrying the `-shadow` authority. Note the upstream in that line is a **canary** pod, and that across many copies both canary pods appear — `LEAST_REQUEST` spreading them, exactly as specified.

---

## Common Mistakes

- **Canary added as a route destination.** It becomes a weighted split and callers reach it. This is the failure the specification calls out explicitly.
- **Giving `stable` its own `trafficPolicy`.** A subset policy replaces the host one; `stable` must inherit.
- **Putting `consistentHash` inside the `stable` subset instead of at host level.** Behaviour can look right and the grader still fails it.
- **Expecting the caller's affinity to govern the mirrored copy.** The copy goes to the canary cluster and obeys *that* cluster's policy.
- **Testing affinity without a baseline of which pods are which.** Record the stable and canary IPs first.
- **Counting shadow log lines without a `BEFORE`.** The log accumulates across attempts.
- **Omitting `mirrorPercentage`.** The default is 100%, but the specification asks for it explicitly.
