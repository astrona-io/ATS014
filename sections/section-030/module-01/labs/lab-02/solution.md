# Solution Walkthrough

One object, four fields deep — and two of those fields are where this lab is won or lost: `portLevelSettings`, because the task asks for the policy there rather than on the host, and `ttl`, because without it Istio never issues the cookie and the whole thing silently does nothing.

---

## Step 1: Read The Starting State

```sh
kubectl -n lb-demo get pods -o wide --show-labels | head
kubectl -n lb-demo get svc httpbin
kubectl -n lb-demo get destinationrule
```

```text
httpbin-stable-...   2/2   Running   10.244.0.11   app=httpbin,version=stable
httpbin-stable-...   2/2   Running   10.244.0.12   app=httpbin,version=stable
httpbin-stable-...   2/2   Running   10.244.0.13   app=httpbin,version=stable
httpbin-canary-...   2/2   Running   10.244.0.14   app=httpbin,version=canary
httpbin-canary-...   2/2   Running   10.244.0.15   app=httpbin,version=canary
NAME      TYPE        PORT(S)
httpbin   ClusterIP   8000/TCP
No resources found in lb-demo namespace.
```

Five endpoints behind one Service on port **8000**. Note that number: `portLevelSettings` wants the *Service* port, not the container port 8080 behind it.

---

## Step 2: Confirm The Baseline Spreads

Before configuring affinity, prove there is none. The proxy's own access log records the endpoint it chose, which is the honest evidence:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   3 10.244.0.11:8080
   2 10.244.0.12:8080
   3 10.244.0.13:8080
   2 10.244.0.14:8080
   2 10.244.0.15:8080
```

All five. That is what you are about to take away — for cookie-carrying clients only.

---

## Step 3: Write The Policy At Port Level

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-httpbin.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
spec:
  host: httpbin
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8000
        loadBalancer:
          consistentHash:
            httpCookie:
              name: session-id
              ttl: 60s
EOF
kubectl apply -f destinationrule-httpbin.yaml
```

Two things to be deliberate about:

* The policy is under **`portLevelSettings`**, not a bare `trafficPolicy.loadBalancer`. Both would work for this Service; the task asks for the port-level form because that is the shape you need when a Service exposes several ports with different characteristics.
* **`ttl: 60s` is not decoration.** With it, Istio issues a `Set-Cookie` to a client that arrives without one. Without it, Istio only hashes a cookie the client already sends — and a browser that has never visited gets no affinity at all, with nothing to tell you why.

```sh
astrona submit
```

---

## Step 4: Confirm It Reached The Proxy

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local --port 8000 -o json | grep -E 'lbPolicy|minimumRingSize'
```

```text
"lbPolicy": "RING_HASH",
```

`RING_HASH` is Envoy's name for `consistentHash`. If this still says `LEAST_REQUEST`, the push has not landed and editing the YAML again will not help.

---

## Step 5: Watch Istio Issue The Cookie

```sh
kubectl -n lb-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://httpbin:8000/get | grep -i set-cookie
```

```text
set-cookie: session-id="a3f1c9d84e2b7016"; Max-Age=60; Path=/
```

The application did not send that. The proxy generated it, because `ttl` told it to.

---

## Step 6: Prove The Pin, And The Fallback

Capture the cookie, then send a dozen requests carrying it:

```sh
COOKIE=$(kubectl -n lb-demo exec deploy/tester -- sh -c \
  "curl -s -D - -o /dev/null http://httpbin:8000/get | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: *\(session-id=[^;]*\).*/\1/p'" | head -1)

kubectl -n lb-demo exec deploy/tester -- sh -c \
  "for i in \$(seq 1 12); do curl -s -o /dev/null -H 'Cookie: $COOKIE' http://httpbin:8000/get; done"
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort -u
```

```text
10.244.0.13:8080
```

One endpoint, twelve times. Now repeat with no cookie at all and the spread from Step 2 comes back — same policy, different requests. That contrast is the whole point: affinity applies to requests that carry the hashed property and to nothing else.

---

## Step 7: Submit

```sh
astrona submit
```

---

## Common Mistakes

* **Omitting `ttl`.** Istio then only hashes a cookie somebody else set. A first-time browser gets no affinity, and nothing reports it.
* **Putting the policy in `trafficPolicy.loadBalancer` instead of `portLevelSettings`.** The task asks for the port-level form explicitly, and the grader checks that the host-level field is empty.
* **Naming port 8080.** `portLevelSettings` takes the **Service** port — 8000. The container port belongs to the endpoints, one layer down.
* **Testing affinity without checking the fallback.** A policy that pins everything, cookie or not, is not what you configured — it usually means you hashed something every request happens to carry.
* **Reading affinity from response bodies.** `go-httpbin` does not tell you which pod answered. The client proxy's access log does.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [ConsistentHashLB API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings-ConsistentHashLB) — the four hash sources, `ttl`, and `minimumRingSize`
- [LoadBalancerSettings API](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings) — the `simple` enum and the `consistentHash` alternative
- [TrafficPolicy portLevelSettings](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-PortTrafficPolicy) — attaching policy to one port instead of the whole host
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
