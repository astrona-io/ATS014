# Solution Walkthrough

This walkthrough follows the task from top to bottom. Each section starts with the numbered item from the task, shows what to do, and ends with a check that proves the item. Do the sections in order. Sections 1 and 2 build the file, and each later section changes or proves one thing.

---

## Start: Read The Situation

The task says that namespace `lb-demo` has `httpbin-stable` (3 replicas), `httpbin-canary` (2 replicas), the Service `httpbin` on port `8000`, and a `tester` client pod. It also says there is no `DestinationRule` and no `VirtualService`. Check that this is true:

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

The Service has five endpoints (the pod addresses behind it). With no `DestinationRule`, Istio spreads requests over all five. Prove it. The `tester` pod has a sidecar proxy, an Envoy proxy that Istio adds to the pod. It writes one access log line per request, and each line names the endpoint it chose. Send 12 requests, wait for the log, and count the endpoints:

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

All five endpoints answered, so there is no session affinity yet. The `sleep 4` matters: the proxy writes the log line a moment after the request.

---

## Item 1: Attach The Policy To Port 8000

> **Task item 1:** A `DestinationRule` named `httpbin` applies its load balancer policy through **`portLevelSettings` for port `8000`**, not as a host-level `loadBalancer`.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. It can set a policy for the whole host, or for one port with `portLevelSettings`. The task asks for the port form. The port number is the Service port, `8000`, not the container port `8080`.

A `portLevelSettings` entry needs a `loadBalancer` inside it, and that is item 2. So you write item 1 and item 2 in the same file. Save this as `destinationrule-httpbin.yaml`. For now, it has no `ttl`:

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
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Check item 1. The port must be `8000`, and the host-level `loadBalancer` must be empty:

```sh
kubectl -n lb-demo get destinationrule httpbin \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}{"\n"}'
kubectl -n lb-demo get destinationrule httpbin \
  -o jsonpath='host-level:[{.spec.trafficPolicy.loadBalancer}]{"\n"}'
```

```text
8000
host-level:[]
```

---

## Item 2: Hash The `session-id` Cookie

> **Task item 2:** That policy uses **`consistentHash`** on an **HTTP cookie** named **`session-id`**.

You already wrote this in the file. `consistentHash` makes the client's proxy calculate a hash from one value of the request, here the cookie `session-id`. The same cookie value always gives the same endpoint. Check what Istio stored:

```sh
kubectl -n lb-demo get destinationrule httpbin \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].loadBalancer.consistentHash}{"\n"}'
```

```text
{"httpCookie":{"name":"session-id"}}
```

Then check that the proxy received the policy. `istiod`, the Istio control plane, sends the configuration to every proxy. Envoy keeps the endpoints of one destination in a cluster, and `lbPolicy` is the algorithm of that cluster:

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local --port 8000 -o json | grep lbPolicy
```

```text
        "lbPolicy": "RING_HASH",
```

`RING_HASH` is Envoy's name for `consistentHash`. If the line still shows `LEAST_REQUEST`, which is Istio's default, wait a few seconds and run the command again.

---

## Item 3: Add A `ttl` So Istio Issues The Cookie

> **Task item 3:** The cookie has a **`ttl`**, so that **Istio issues the cookie itself** to a client that arrives without one. A client that has never been seen before must receive a `Set-Cookie` on its first response.

The task warns that without `ttl`, Istio only hashes a cookie the client already sends. See the problem first. Send one request with no cookie and count the `set-cookie` lines in the response headers:

```sh
kubectl -n lb-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://httpbin:8000/get | grep -ic set-cookie
```

```text
0
```

There is no `Set-Cookie` header, although the policy exists. Nothing reports an error. Fix it: add `ttl: 60s` under `httpCookie` in `destinationrule-httpbin.yaml`, so the file looks like this:

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

Apply it again:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin configured
```

Check item 3. Send a request with no cookie and print the `set-cookie` header:

```sh
kubectl -n lb-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://httpbin:8000/get | grep -i set-cookie
```

```text
set-cookie: session-id="cee0ad34d462cb0e"; Max-Age=60; HttpOnly
```

The application did not send this header. The sidecar proxy added it because of the `ttl`. `Max-Age=60` is the 60 seconds from the `ttl`. Your cookie value will differ.

---

## Item 4: A Returning Client Reaches One Endpoint

> **Task item 4:** A client that returns the cookie is **pinned to a single endpoint** across repeated requests.

Act as a browser that returns its cookie. First save the cookie that Istio issues in a shell variable:

```sh
COOKIE=$(kubectl -n lb-demo exec deploy/tester -- sh -c \
  "curl -s -D - -o /dev/null http://httpbin:8000/get | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: *\(session-id=[^;]*\).*/\1/p'" | head -1)
echo $COOKIE
```

```text
session-id="8d51723576402411"
```

Send 12 requests that carry this cookie. Then count the endpoints in the access log:

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

All 12 requests reached one endpoint. The proxy hashed the same cookie value each time and chose the same endpoint each time.

---

## Item 5: A Client Without The Cookie Is Not Pinned

> **Task item 5:** A client that sends **no** cookie is **not** pinned: those requests spread across endpoints.

Send 12 requests with no cookie, and count the endpoints:

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

The requests spread over all five endpoints. The policy is the same as in item 4. Only the requests differ. A request without a cookie gives the proxy nothing to hash, so it uses normal load balancing.

---

## Item 6: Leave The Deployments And The Service Alone

> **Task item 6:** Leave the Deployments and the Service unchanged. Do not change replica counts or the Service selector.

You only created one `DestinationRule`. Confirm that nothing else changed:

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

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-02
```

The grader reads the `DestinationRule`, asks the `tester` proxy for the `lbPolicy`, sends real requests, and counts the endpoints.

---

## Mistakes That Fail The Grader

- **Leaving out `ttl` (item 3).** Istio then never issues the cookie. The grader finds no `Set-Cookie` header on a request without a cookie.
- **Putting the policy in `trafficPolicy.loadBalancer` (item 1).** The grader checks that the host-level `loadBalancer` is empty.
- **Using port `8080` (item 1).** `portLevelSettings` takes the Service port `8000`. Port `8080` is the container port of the endpoints.
- **Naming the cookie something else (item 2).** The grader looks for `session-id`.
- **Reading the access log too early (items 4 and 5).** The proxy writes the log line a moment after the request. Wait a few seconds, or you count old requests.
- **Submitting straight after `kubectl apply`.** `istiod` needs a moment to send the policy to the proxy. If the grader still sees a policy other than `RING_HASH`, wait a few seconds and submit again.
