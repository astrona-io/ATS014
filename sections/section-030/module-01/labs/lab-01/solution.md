# Solution Walkthrough

Mission debrief, astronaut. Two objects. The interesting part is the second `trafficPolicy` — the one on the subset — because it replaces the host policy rather than adding to it, and the grader checks that you put it in exactly one place.

---

## Step 1: Read the Starting State

```sh
kubectl -n lb-demo get pods -o wide --show-labels | head
kubectl -n lb-demo get endpoints httpbin
```

```text
httpbin-canary-6b7d8f9c4-lq2wn   2/2   Running   10.244.0.16   app=httpbin,version=canary
httpbin-canary-6b7d8f9c4-x8plm   2/2   Running   10.244.0.17   app=httpbin,version=canary
httpbin-stable-79c5d6b84-2knzp   2/2   Running   10.244.0.11   app=httpbin,version=stable
httpbin-stable-79c5d6b84-7wqrt   2/2   Running   10.244.0.12   app=httpbin,version=stable
httpbin-stable-79c5d6b84-m4xvd   2/2   Running   10.244.0.13   app=httpbin,version=stable
NAME      ENDPOINTS                                                              AGE
httpbin   10.244.0.11:8080,10.244.0.12:8080,10.244.0.13:8080 + 2 more...         5m
```

Five endpoints behind one Service. Establish the baseline — with no policy, the same user spreads:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
   3 10.244.0.11:8080
   2 10.244.0.12:8080
   3 10.244.0.13:8080
   2 10.244.0.16:8080
   2 10.244.0.17:8080
```

---

## Step 2: The DestinationRule, With Policies at Two Levels

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-user
  subsets:
    - name: stable
      labels:
        version: stable
    - name: canary
      labels:
        version: canary
      trafficPolicy:
        loadBalancer:
          simple: ROUND_ROBIN
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Three placement details the grader checks:

- **`consistentHash` is at `spec.trafficPolicy`** — the host level, so it applies to every subset that does not override it.
- **`ROUND_ROBIN` is inside the `canary` subset entry**, indented under that subset's own `trafficPolicy`.
- **The `stable` subset has no `trafficPolicy` at all.** Adding one would *replace* the host policy for `stable` — and if you only wrote `loadBalancer` in it you would still be fine here, but the habit is dangerous: a subset policy never inherits, so anything else the host policy carried would be silently dropped.

---

## Step 3: The VirtualService

Save this as `virtualservice-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  hosts:
    - httpbin
  http:
    - match:
        - headers:
            x-track:
              exact: "canary"
      route:
        - destination:
            host: httpbin
            subset: canary
    - route:
        - destination:
            host: httpbin
            subset: stable
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

Then check the result:

```sh
istioctl analyze -n lb-demo
```

```text
✔ No validation issues found when analyzing namespace: lb-demo.
```

The default rule is last, as always.

---

## Step 4: Confirm the Two Clusters Have Different Policies

This is the structural proof that the subset override took effect, and it is faster than any behavioural test:

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local -o json \
  | grep -E '"name"|lbPolicy'
```

```text
"name": "outbound|8000||httpbin.lb-demo.svc.cluster.local",
"lbPolicy": "RING_HASH",
"name": "outbound|8000|canary|httpbin.lb-demo.svc.cluster.local",
"lbPolicy": "ROUND_ROBIN",
"name": "outbound|8000|stable|httpbin.lb-demo.svc.cluster.local",
"lbPolicy": "RING_HASH",
```

Three clusters: the subset-less one and one per subset. `stable` inherited `RING_HASH` from the host policy; `canary` shows `ROUND_ROBIN` because its own policy replaced it. `RING_HASH` is Envoy's name for `consistentHash`.

---

## Step 5: Verify the Three Behaviours

**Affinity on stable** — same user, twelve times, one pod:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.12:8080
```

**The canary override** — same user, but routed to the canary subset, must spread:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice" -H "x-track: canary"; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
   6 10.244.0.16:8080
   6 10.244.0.17:8080
```

Identical `x-user`, completely different behaviour — because the cluster it landed in uses a different algorithm.

**Nothing to hash** — no `x-user` at all:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
   4 10.244.0.11:8080
   5 10.244.0.12:8080
   3 10.244.0.13:8080
```

The policy is unchanged and still `RING_HASH`; these requests simply have nothing to hash, so the proxy falls back to normal load balancing. This is the failure mode behind most "affinity works in testing but not in production" reports.

---

## Common Mistakes

- **Putting `consistentHash` inside the `stable` subset instead of at host level.** It works for `stable` and the grader still fails you, because the host-level policy is what the specification asked for.
- **Adding a `trafficPolicy` to the `stable` subset.** A subset policy replaces the host one; anything else the host carried is dropped for that subset.
- **Setting `simple` and `consistentHash` in the same `loadBalancer`.** Mutually exclusive — the object is rejected.
- **Testing affinity against one replica.** Every request hits the same pod regardless of policy.
- **Expecting affinity for requests without the header.** They fall back to spreading, silently.
- **Putting the default rule above the `x-track` rule.** First match wins; the canary rule never runs.
- **Reading affinity from the application response.** `go-httpbin` does not report which pod answered — the client proxy's access log does.
