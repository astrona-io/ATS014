# Solution Walkthrough

The task has six items. One `DestinationRule` solves items 1 to 3. Steps 4 to 8 then prove items 3 to 6 with real requests. A `DestinationRule` is the Istio object that holds policies for traffic to one host, including the load balancing policy.

| Task item | What it asks | Where you solve or prove it |
| --- | --- | --- |
| 1 | Set the policy in `portLevelSettings` for port `8000` | Step 3 |
| 2 | Hash an HTTP cookie named `session-id` | Step 3 |
| 3 | Add a `ttl` so Istio issues the cookie | Step 3, proved in Step 5 |
| 4 | A client that returns the cookie reaches one endpoint | Step 6 |
| 5 | A client without the cookie is spread over endpoints | Step 7 |
| 6 | Leave the Deployments and the Service unchanged | Step 8 |

---

## Step 1: Read The Starting State

Look at what runs in the `lb-demo` namespace before you change anything:

```sh
kubectl -n lb-demo get deploy
kubectl -n lb-demo get svc httpbin
kubectl -n lb-demo get destinationrule
```

```text
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
httpbin-canary   2/2     2            2           42s
httpbin-stable   3/3     3            3           42s
tester           1/1     1            1           42s
NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
httpbin   ClusterIP   10.96.119.56   <none>        8000/TCP   42s
No resources found in lb-demo namespace.
```

The Service `httpbin` has five endpoints (the pod addresses behind it): three stable pods and two canary pods. It listens on port `8000`. Remember that number. `portLevelSettings` takes the Service port, not the container port `8080` behind it.

There is no `DestinationRule` yet, so Istio uses its default load balancer and spreads requests over all five endpoints.

---

## Step 2: Prove That There Is No Affinity Yet

Session affinity means one client keeps reaching the same pod. Check that it does not exist yet. The `tester` pod has a sidecar proxy, an Envoy proxy that Istio adds to the pod. It writes one access log line for each request, and each line names the endpoint it chose.

Send 12 requests, wait a few seconds, then count the endpoints in the log:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   3 10.244.0.10:8080
   5 10.244.0.11:8080
   1 10.244.0.12:8080
   1 10.244.0.8:8080
   2 10.244.0.9:8080
```

All five endpoints answered. The `sleep 4` matters: the proxy writes the log line a moment after the request. Without the wait, you read old lines.

---

## Step 3: Write The Policy (Items 1, 2 And 3)

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

```text
destinationrule.networking.istio.io/httpbin created
```

Each task item matches one part of the file:

- **Item 1:** `portLevelSettings` with `port.number: 8000` sets the policy for one port of the Service. The `loadBalancer` field sits inside it, not directly under `trafficPolicy`. The number is the Service port `8000`.
- **Item 2:** `consistentHash` with `httpCookie` and `name: session-id` makes the client's proxy calculate a hash from the `session-id` cookie. The same cookie value always gives the same endpoint.
- **Item 3:** `ttl: 60s` makes Istio create the cookie. Without `ttl`, Istio only hashes a cookie that the client already sends. A browser that has never visited gets no cookie and no affinity, and nothing reports an error.

---

## Step 4: Check That The Proxy Received The Policy

`istiod`, the Istio control plane, sends the new configuration to every sidecar proxy. Ask the `tester` proxy what it holds for the Service. Envoy keeps the endpoints of one destination in a cluster, and `lbPolicy` is the algorithm of that cluster:

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local --port 8000 -o json | grep -E 'lbPolicy|minimumRingSize'
```

```text
        "lbPolicy": "RING_HASH",
            "minimumRingSize": "1024"
```

`RING_HASH` is Envoy's name for `consistentHash`. If the line still shows `LEAST_REQUEST`, which is Istio's default, `istiod` has not sent the configuration yet. Wait a few seconds and run the command again.

---

## Step 5: Prove Item 3, Istio Issues The Cookie

Send one request with no cookie and print the response headers:

```sh
kubectl -n lb-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://httpbin:8000/get | grep -i set-cookie
```

```text
set-cookie: session-id="4f4a4c5030b7b025"; Max-Age=60; HttpOnly
```

The application did not send this header. The sidecar proxy added it, because the policy has a `ttl`. `Max-Age=60` is the `ttl` of 60 seconds. Your cookie value will differ.

---

## Step 6: Prove Item 4, A Returning Client Reaches One Endpoint

First save the cookie that Istio issues in a shell variable:

```sh
COOKIE=$(kubectl -n lb-demo exec deploy/tester -- sh -c \
  "curl -s -D - -o /dev/null http://httpbin:8000/get | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: *\(session-id=[^;]*\).*/\1/p'" | head -1)
echo $COOKIE
```

```text
session-id="8d51723576402411"
```

Now send 12 requests that carry this cookie, and count the endpoints in the log:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  "for i in \$(seq 1 12); do curl -s -o /dev/null -H 'Cookie: $COOKIE' http://httpbin:8000/get; done"
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.10:8080
```

All 12 requests reached one endpoint. The proxy hashed the same cookie value each time and got the same endpoint each time.

---

## Step 7: Prove Item 5, A Client Without The Cookie Is Not Pinned

Send 12 requests with no cookie:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   3 10.244.0.10:8080
   3 10.244.0.11:8080
   1 10.244.0.12:8080
   3 10.244.0.8:8080
   2 10.244.0.9:8080
```

The requests spread over all five endpoints again. The policy is the same as in Step 6. Only the requests differ. Every request in this step starts a new session, so the proxy has no cookie to hash and picks an endpoint with its normal load balancing.

---

## Step 8: Check Item 6, The Workloads Are Unchanged

You did not edit a Deployment or the Service. Confirm it:

```sh
kubectl -n lb-demo get deploy
kubectl -n lb-demo get svc httpbin -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
httpbin-canary   2/2     2            2           51s
httpbin-stable   3/3     3            3           51s
tester           1/1     1            1           51s
{"app":"httpbin"}
```

`httpbin-stable` still has 3 replicas, `httpbin-canary` still has 2, and the Service still selects pods on `app` only.

---

## Step 9: Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-02
```

The grader reads the `DestinationRule`, asks the `tester` proxy for the `lbPolicy`, sends real requests, and counts the endpoints.

---

## Mistakes That Fail The Grader

- **Leaving out `ttl`.** Istio then never issues the cookie. The grader finds no `Set-Cookie` header on a request without a cookie.
- **Putting the policy in `trafficPolicy.loadBalancer`.** The task asks for the port-level form. The grader checks that the host-level `loadBalancer` is empty.
- **Using port `8080`.** `portLevelSettings` takes the Service port `8000`. Port `8080` is the container port of the endpoints.
- **Naming the cookie something else.** The grader looks for `session-id`.
- **Reading the access log too early.** The proxy writes the log line a moment after the request. Wait a few seconds before you count endpoints, or you count old requests.
- **Submitting straight after `kubectl apply`.** `istiod` needs a moment to send the policy to the proxy. If the grader still sees a policy other than `RING_HASH`, wait a few seconds and submit again.
