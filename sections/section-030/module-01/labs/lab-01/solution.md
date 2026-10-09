# Solution Walkthrough

You need two objects: a `DestinationRule` (the Istio object that holds policies for traffic to one host) and a `VirtualService` (the Istio object that holds routing rules). The important part is the second `trafficPolicy`, the one on the `canary` subset. Its `loadBalancer` replaces the host's `loadBalancer` for that subset, and the grader checks that you put it in exactly one place.

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

The Service has five endpoints (pod addresses). First record the starting behaviour. With no policy, the requests of the same user spread over the pods. The `tester` pod's sidecar proxy writes an access log line for each request, and each line names the endpoint it picked:

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

Write the manifest to a file and apply the file. In the exam, a file lets you read, edit and apply the configuration again.

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

The grader checks three placement details:

- **`consistentHash` is at `spec.trafficPolicy`**, the host level, so it applies to every subset that does not override it. `consistentHash` makes the sending proxy pick the pod from a hash of the `x-user` header, so the same user always reaches the same pod.
- **`ROUND_ROBIN` is inside the `canary` subset entry**, under that subset's own `trafficPolicy`.
- **The `stable` subset has no `trafficPolicy` at all.** It inherits the host's `consistentHash` as it is. Any field a subset policy sets replaces the host's whole field for that subset, so a `loadBalancer` on `stable` would remove its session affinity.

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

The rule without a `match` is last. The proxy uses the first rule that matches, so a rule without a `match` above the `x-track` rule would catch every request.

---

## Step 4: Confirm the Two Clusters Have Different Policies

Envoy stores the endpoints of one destination as a **cluster**: one for the whole host and one per subset. Each cluster has an `lbPolicy` field. Reading it proves that the subset override reached the proxy, and it is faster than any test with live requests:

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

There are three clusters: the one without a subset and one per subset. `stable` inherited `RING_HASH` from the host policy. `RING_HASH` is Envoy's name for `consistentHash`. `canary` uses round robin, because its own policy replaced the host's. Round robin is Envoy's own default, and the dump often leaves default values out. If your dump shows no `lbPolicy` line under the `canary` cluster, that also means round robin, and the grader reads it that way.

---

## Step 5: Verify the Three Behaviours

**Session affinity on `stable`.** Send the same user twelve times; all requests must reach one pod:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.12:8080
```

**The `canary` override.** Send the same user, but routed to the `canary` subset. The requests must spread:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice" -H "x-track: canary"; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 | grep -oE '[0-9.]+:8080' | sort | uniq -c
```

```text
   6 10.244.0.16:8080
   6 10.244.0.17:8080
```

The `x-user` value is the same, but the behaviour is completely different, because the `canary` cluster uses a different algorithm.

**Nothing to hash.** Send requests with no `x-user` header at all:

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

The policy is unchanged and still `RING_HASH`. These requests have nothing to hash, so the proxy falls back to normal load balancing. This is the cause behind most "session affinity works in testing but not in production" reports.

When all three checks look right, send the lab for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-01
```

---

## Common Mistakes

- **Putting `consistentHash` inside the `stable` subset instead of at host level.** It works for `stable`, but the grader still fails it, because the task asks for the host-level policy.
- **Adding a `loadBalancer` to the `stable` subset.** A field the subset sets replaces the host's whole field, so `stable` would lose the host's `consistentHash`.
- **Setting `simple` and `consistentHash` in the same `loadBalancer`.** You can only use one; Istio rejects the object.
- **Testing session affinity against one replica.** Every request reaches the same pod, whatever the policy.
- **Expecting session affinity for requests without the header.** The proxy spreads them, with no error.
- **Putting the rule without a `match` above the `x-track` rule.** The first matching rule wins, so the `canary` rule never runs.
- **Reading session affinity from the application response.** `go-httpbin` does not report which pod answered. The client proxy's access log does.
