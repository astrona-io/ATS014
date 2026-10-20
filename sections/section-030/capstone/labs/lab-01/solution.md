# Solution Walkthrough

You build two objects. The `DestinationRule` carries a policy at two levels (items 1 to 4). The `VirtualService` carries two features on one rule: a route and a mirror (items 5 to 7). Neither half tells you whether the other half worked, so items 8 to 13 check several separate things with real requests and with the configuration of the proxy.

---

## Start: Read The Starting State

The task describes two versions of `httpbin` behind one Service, and no Istio objects. Check the pods with their addresses, the Deployments, the Service, and the access log of the canary pods:

```sh
kubectl -n sessions get pods -o wide -L version | awk '{print $1,$2,$3,$6,$NF}'
kubectl -n sessions get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n sessions get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl -n sessions get destinationrule,virtualservice
sleep 5
kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c 'GET /get'
```

```text
NAME READY STATUS IP VERSION
httpbin-canary-74d4dc88d6-5kcjh 2/2 Running 10.244.0.10 canary
httpbin-canary-74d4dc88d6-sx5gp 2/2 Running 10.244.0.12 canary
httpbin-stable-bc949f8cc-fcxc4 2/2 Running 10.244.0.8 stable
httpbin-stable-bc949f8cc-t9kgc 2/2 Running 10.244.0.11 stable
httpbin-stable-bc949f8cc-tw5bv 2/2 Running 10.244.0.9 stable
tester-69699fd775-56f25 2/2 Running 10.244.0.13 <none>
NAME             REPLICAS   UID
httpbin-canary   2          da177095-40b0-4168-a069-8829bf32a71a
httpbin-stable   3          80b8184f-fd11-455a-ac2f-9cd3dbd3b479
tester           1          4f99a89b-a83c-4fe1-80f2-1387ad07b722
{"app":"httpbin"} 8000
No resources found in sessions namespace.
0
```

The `awk` command keeps five columns of the pod list: the name, the ready count, the status, the IP address and the `version` label. Write down the two canary addresses, `10.244.0.10` and `10.244.0.12`. The grader checks that no caller response comes from them, and so should you. The `0` on the last line is the number of `GET /get` lines in the access logs of the canary pods before you start. The `UID` values and the replica counts are for item 13.

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).

A `DestinationRule` is the Istio object that holds policies for traffic to one host, and it defines subsets. A subset is a named group of pods, picked by labels. Start with the subsets only. Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: sessions
spec:
  host: httpbin
  subsets:
    - name: stable
      labels:
        version: stable
    - name: canary
      labels:
        version: canary
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Check item 1:

```sh
kubectl -n sessions get destinationrule httpbin -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
stable=stable
canary=canary
```

---

## Item 2: Hash The `x-session` Header At Host Level

> **Task item 2:** A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-session`**.

`consistentHash` makes the sending proxy calculate a hash from the header `x-session` and pick the endpoint from that hash. The same session then always reaches the same pod. Add the policy at the host level, which is `spec.trafficPolicy`. Edit `destinationrule-httpbin.yaml`:

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
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin configured
```

Check item 2. Print the host-level policy, and read the `lbPolicy` of each cluster in the proxy of `tester`. The proxy is the Envoy container that Istio adds to each pod. A cluster is Envoy's name for the endpoints of one destination, and `lbPolicy` is its load balancing algorithm:

```sh
kubectl -n sessions get destinationrule httpbin -o jsonpath='{.spec.trafficPolicy}{"\n"}'
istioctl proxy-config cluster deploy/tester -n sessions \
  --fqdn httpbin.sessions.svc.cluster.local -o json | grep -E '"name": "outbound|lbPolicy'
```

```text
{"loadBalancer":{"consistentHash":{"httpHeaderName":"x-session"}}}
        "name": "outbound|8000||httpbin.sessions.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|canary|httpbin.sessions.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|stable|httpbin.sessions.svc.cluster.local",
        "lbPolicy": "RING_HASH",
```

All three clusters use `RING_HASH`, which is Envoy's name for `consistentHash`. If a cluster still shows another policy, `istiod`, the Istio control plane, has not sent the change yet. Wait a few seconds and run the command again.

---

## Items 3 And 4: Override The Policy For `canary`, Keep `stable` Plain

> **Task item 3:** A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: LEAST_REQUEST`**. The canary is being load tested, so it must spread rather than pin.
>
> **Task item 4:** The `stable` subset must carry **no** `trafficPolicy` of its own. It inherits the host-level one.

Both items change the subsets in one file. Add a `trafficPolicy` inside the `canary` subset, and leave `stable` as it is. A field that a subset sets replaces the whole field of the host for that subset. A `loadBalancer` on `stable` would have to repeat the hashing, and the task requires that `stable` inherits it. Edit `destinationrule-httpbin.yaml` into its final form:

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

```text
destinationrule.networking.istio.io/httpbin configured
```

Check items 3 and 4. Print the policy of each subset:

```sh
kubectl -n sessions get destinationrule httpbin \
  -o jsonpath='{range .spec.subsets[*]}{.name}{" "}{.trafficPolicy}{"\n"}{end}'
```

```text
stable 
canary {"loadBalancer":{"simple":"LEAST_REQUEST"}}
```

`stable` has no policy of its own, and `canary` has `LEAST_REQUEST`.

---

## Items 5 And 6: One Rule That Routes 100% To `stable`

> **Task item 5:** A `VirtualService` named `httpbin` for host `httpbin` with exactly **one** `http` rule.
>
> **Task item 6:** That rule routes **100% of caller traffic to subset `stable`**.

A `VirtualService` holds the routing rules for a host. Start with the route only. Save this as `virtualservice-httpbin.yaml`:

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
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin.yaml
```

```text
virtualservice.networking.istio.io/httpbin created
```

Check items 5 and 6. Print the `http` list:

```sh
kubectl -n sessions get virtualservice httpbin -o jsonpath='{.spec.http}{"\n"}'
```

```text
[{"route":[{"destination":{"host":"httpbin","subset":"stable"}}]}]
```

The list holds exactly one rule, and its only destination is the subset `stable`. A route with one destination sends all the traffic there, so the weight is 100%. The canary gets nothing yet. Count the `GET /get` lines in the canary logs again, and the result is still `0`.

---

## Item 7: Mirror The Rule To `canary`

> **Task item 7:** The same rule **mirrors** its requests to subset **`canary`**, with `mirrorPercentage` set explicitly to **100**.

Mirroring means that the proxy of the caller sends a copy of each request to a second destination and ignores the response of the copy. Add `mirror` and `mirrorPercentage` to the same rule. They are siblings of `route`, at the same indentation. If you add `canary` as a second entry in `route`, it becomes a weighted destination, callers start to reach canary pods, and the grader fails. Edit `virtualservice-httpbin.yaml`:

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

```text
virtualservice.networking.istio.io/httpbin configured
```

Check item 7. Print the mirror fields, and let Istio check the objects:

```sh
kubectl -n sessions get virtualservice httpbin -o jsonpath='{.spec.http[0].mirror} {.spec.http[0].mirrorPercentage}{"\n"}'
istioctl analyze -n sessions
```

```text
{"host":"httpbin","subset":"canary"} {"value":100}

✔ No validation issues found when analyzing namespace: sessions.
```

The rule mirrors to `canary` at 100%.

---

## Item 8: One Session Reaches One Stable Pod

> **Task item 8:** Twelve requests carrying the same `x-session` value all reach **one single stable endpoint**.

The access log of the `tester` proxy has one line per request, and each line names the endpoint it chose. Send 12 requests with the same session, wait for the log, and count the endpoints:

```sh
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-session: alice"; done'
sleep 4
kubectl -n sessions logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.11:8080
```

All 12 requests reached one endpoint, and `10.244.0.11` is a stable pod. Neither canary address appears. The mirrored copy does not show in the upstream field of this log, because for the caller the request went to `stable`.

---

## Item 9: Requests Without A Header Spread

> **Task item 9:** Twelve requests with **no** `x-session` header reach more than one endpoint, because a request with nothing to hash gets normal load balancing.

```sh
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
sleep 4
kubectl -n sessions logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   5 10.244.0.11:8080
   4 10.244.0.8:8080
   3 10.244.0.9:8080
```

The requests spread over the three stable pods. The policy is the same `RING_HASH`. These requests have nothing to hash, so the proxy uses normal load balancing.

---

## Item 10: No Caller Response Comes From A Canary Pod

> **Task item 10:** No caller response comes from a canary pod: the canary must be a mirror target, not a route destination.

Two facts prove it. The `route` list of the rule holds only `stable`, and the upstream addresses in the caller log (items 8 and 9) are stable addresses:

```sh
kubectl -n sessions get virtualservice httpbin -o jsonpath='{range .spec.http[0].route[*]}{.destination.subset}{" "}{end}{"\n"}'
kubectl -n sessions get pods -l version=canary -o wide | awk '{print $1,$6}'
```

```text
stable 
NAME IP
httpbin-canary-74d4dc88d6-5kcjh 10.244.0.10
httpbin-canary-74d4dc88d6-sx5gp 10.244.0.12
```

The route lists only `stable`. The canary addresses `10.244.0.10` and `10.244.0.12` do not appear in the outputs of items 8 and 9.

---

## Item 11: The Canary Receives The Copies

> **Task item 11:** The canary receives a copy of nearly every request: for 40 requests sent, the canary pods' proxy access logs show at least 30 new `GET /get` lines. No caller traffic is routed to the canary, so every request it logs is a mirrored copy.

In Istio 1.30.5, the mirrored copy does not get a `-shadow` suffix on its `Host` header, so you cannot search for that suffix. Count the `GET /get` lines instead. The access logs keep growing across your attempts, so count before and after. Wait before each count, because the proxy writes a log line a moment after the request:

```sh
sleep 5
BEFORE=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c 'GET /get')
kubectl -n sessions exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -H "x-session: alice" http://httpbin:8000/get; done'
sleep 5
AFTER=$(kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 | grep -c 'GET /get')
echo "mirrored: $((AFTER - BEFORE)) of 40"
kubectl -n sessions logs -l app=httpbin,version=canary -c istio-proxy --tail=1
```

```text
mirrored: 40 of 40
[2026-10-20T20:51:01.344Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 733 0 0 "10.244.0.13" "curl/8.23.0" "97309c36-95b0-9bb0-b7fe-263b28c8aedc" "httpbin:8000" "10.244.0.10:8080" inbound|8080|| 127.0.0.6:53361 10.244.0.10:8080 10.244.0.13:0 outbound_.8000_.canary_.httpbin.sessions.svc.cluster.local default
[2026-10-20T20:51:01.330Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 733 0 0 "10.244.0.13" "curl/8.23.0" "4b482c19-6457-91a9-b190-aa1cb0683b72" "httpbin:8000" "10.244.0.12:8080" inbound|8080|| 127.0.0.6:35533 10.244.0.12:8080 10.244.0.13:0 outbound_.8000_.canary_.httpbin.sessions.svc.cluster.local default
```

All 40 requests were copied to the canary. Each log line names its canary pod as the upstream, and the request came from the `tester` pod (`10.244.0.13`) through its `canary` cluster. Both canary pods appear, because `LEAST_REQUEST` spreads the copies, as the task asks for the canary.

---

## Item 12: Different Policies, And A Mirror Policy In The Proxy

> **Task item 12:** The `stable` and `canary` clusters report **different** `lbPolicy` values in the `tester` pod's proxy configuration (`istioctl proxy-config cluster`), and the `tester` pod's routes hold a mirror policy.

```sh
istioctl proxy-config cluster deploy/tester -n sessions \
  --fqdn httpbin.sessions.svc.cluster.local -o json | grep -E '"name": "outbound|lbPolicy'
istioctl proxy-config routes deploy/tester -n sessions -o json | grep -c requestMirrorPolicies
```

```text
        "name": "outbound|8000||httpbin.sessions.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|canary|httpbin.sessions.svc.cluster.local",
        "lbPolicy": "LEAST_REQUEST",
        "name": "outbound|8000|stable|httpbin.sessions.svc.cluster.local",
        "lbPolicy": "RING_HASH",
2
```

`stable` has `RING_HASH`, which it inherited, and `canary` has `LEAST_REQUEST` from its own policy. The two values are different. The proxy sends the mirrored copy to the `canary` cluster, so `LEAST_REQUEST` decides which canary pod gets each copy. The session of the caller has no effect on it. The count `2` means that the route tables of the `tester` proxy hold the mirror policy. There are two route tables for the host, named `80` and `8000`. Any number above `0` means that the mirror reached the proxy.

---

## Item 13: Nothing Else Changed

> **Task item 13:** Replica counts are unchanged (3 and 2), and the Service selector still selects on `app` only.

```sh
kubectl -n sessions get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n sessions get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME             REPLICAS   UID
httpbin-canary   2          da177095-40b0-4168-a069-8829bf32a71a
httpbin-stable   3          80b8184f-fd11-455a-ac2f-9cd3dbd3b479
tester           1          4f99a89b-a83c-4fe1-80f2-1387ad07b722
{"app":"httpbin"} 8000
```

The replica counts are 3 and 2, the `UID` values are the same as at the start, and the Service selects on `app` only.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-030/capstone/labs/lab-01
```

The grader sends real requests, reads the clusters and the routes of the `tester` proxy, and counts the copies in the canary logs.

---

## Mistakes That Fail The Grader

- **The canary added as a route destination (items 6, 7 and 10).** It becomes a weighted split, and callers reach it. The task calls this out explicitly.
- **Giving `stable` its own `trafficPolicy` (item 4).** The task requires that `stable` inherits the host policy.
- **Putting `consistentHash` inside the `stable` subset instead of at host level (item 2).** The behaviour can look right, but the task asks for the host-level policy.
- **Expecting the session of the caller to control the mirrored copy (item 12).** The copy goes to the `canary` cluster and follows the policy of that cluster.
- **Testing affinity without knowing which pods are which (items 8 and 10).** Write down the stable and canary addresses first.
- **Counting the canary log lines without a count before the test (item 11).** The log keeps growing across attempts.
- **Leaving out `mirrorPercentage` (item 7).** The default is 100%, but the task asks for it explicitly, and the grader checks it.
