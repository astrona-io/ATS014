# Solution Walkthrough

You need one `DestinationRule`, the Istio object that holds policies for traffic to one host. Two of its fields decide this lab. `portLevelSettings` matters because the task asks for the policy there rather than on the host. `ttl` matters because without it the sidecar proxy never creates the cookie, and the policy silently does nothing.

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

The Service has five endpoints (pod addresses) and listens on port **8000**. Note that number: `portLevelSettings` takes the *Service* port, not the container port 8080 behind it.

---

## Step 2: Confirm The Baseline Spreads

Before you configure session affinity, prove there is none. The `tester` pod's sidecar proxy writes an access log line for each request, and each line names the endpoint it chose. That log is the reliable proof:

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

All five endpoints answered. The policy will change that, but only for clients that send the cookie.

---

## Step 3: Write The Policy At Port Level

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
    portLevelSettings:
      - port:
          number: 8000
        loadBalancer:
          consistentHash:
            httpCookie:
              name: session-id
              ttl: 60s
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

Two details matter here:

* The policy is under **`portLevelSettings`**, not directly under `trafficPolicy.loadBalancer`. Both would work for this Service. The task asks for the port-level form, because you need it when a Service exposes several ports that behave differently.
* **`ttl: 60s` is required here.** With it, the sidecar proxy adds a `Set-Cookie` header to the response for a client that arrives without the cookie. Without it, Istio only hashes a cookie the client already sends, and a browser that has never visited gets no session affinity at all, with no error.

---

## Step 4: Confirm It Reached The Proxy

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local --port 8000 -o json | grep -E 'lbPolicy|minimumRingSize'
```

```text
"lbPolicy": "RING_HASH",
```

Envoy stores the endpoints of one destination as a **cluster**, and `lbPolicy` is the algorithm of that cluster. `RING_HASH` is Envoy's name for `consistentHash`. If this still says `LEAST_REQUEST` (Istio's default), `istiod` has not yet sent the new configuration to the proxy. Wait a few seconds; editing the YAML again does not help.

---

## Step 5: Watch Istio Issue The Cookie

```sh
kubectl -n lb-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://httpbin:8000/get | grep -i set-cookie
```

```text
set-cookie: session-id="a3f1c9d84e2b7016"; Max-Age=60; Path=/
```

The application did not send that header. The `httpbin` pod's sidecar proxy created it, because the policy sets `ttl`.

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

All twelve requests reached one endpoint. Now repeat the loop with no cookie at all, and the spread from Step 2 comes back. The policy is the same, but the requests differ. Session affinity applies only to requests that carry the hashed value.

---

## Step 7: Submit

```sh
astrona submit -c sections/section-030/module-01/labs/lab-02
```

---

## Common Mistakes

* **Leaving out `ttl`.** Istio then only hashes a cookie that something else set. A first-time browser gets no session affinity, and nothing reports it.
* **Putting the policy in `trafficPolicy.loadBalancer` instead of `portLevelSettings`.** The task asks for the port-level form explicitly, and the grader checks that the host-level field is empty.
* **Naming port 8080.** `portLevelSettings` takes the **Service** port, 8000. Port 8080 is the container port of the endpoints.
* **Testing session affinity without checking the fallback.** A policy that pins every request, with or without the cookie, is not what you configured. It usually means you hashed a value that every request carries.
* **Reading session affinity from response bodies.** `go-httpbin` does not report which pod answered. The client proxy's access log does.
