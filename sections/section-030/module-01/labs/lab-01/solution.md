# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. You grow one `DestinationRule` file in three steps: the subsets (item 1), the host-level policy (item 2), and the subset-level override (item 3). Then you write the `VirtualService` (item 4). Items 5 to 10 prove the behaviour with real requests and with the configuration of the proxy.

---

## Start: Read The Starting State

The task describes two versions of `httpbin` behind one Service, and no `DestinationRule` or `VirtualService`. Check that this is true, and send 12 requests from the `tester` pod. The sidecar proxy of `tester` is the Envoy container that Istio adds to the pod. It writes one access log line per request, and each line names the endpoint it chose. An endpoint is the address of one pod. Wait a few seconds before you read the log, because the proxy writes the line a moment after the request:

```sh
kubectl -n lb-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n lb-demo get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl -n lb-demo get destinationrule,virtualservice
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
NAME             REPLICAS   UID
httpbin-canary   2          8c8b3e2b-c439-4408-83e8-91e5774ce6df
httpbin-stable   3          93fc2b79-d134-41af-ad78-b3aa9087166d
tester           1          7b0e3d1b-6e82-4f4a-883a-48dfb51a23c6
{"app":"httpbin"} 8000
No resources found in lb-demo namespace.
   2 10.244.0.10:8080
   6 10.244.0.11:8080
   2 10.244.0.13:8080
   2 10.244.0.9:8080
```

The Deployments have 3 and 2 replicas, and the Service selects on `app` only. With no policy, the 12 requests of one user spread over several pods. Items 9 and 10 compare against the replica counts and the `UID` values above.

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `httpbin` for host `httpbin`, defining exactly two subsets: **`stable`** (`version: stable`) and **`canary`** (`version: canary`).

A `DestinationRule` is the Istio object that holds policies for traffic to one host. It also defines subsets, which are named groups of pods picked by labels. Start with the subsets only. Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: lb-demo
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

Check item 1. Print the subsets, and list the clusters in the proxy of `tester`. A cluster is Envoy's name for the endpoints of one destination. There is one for the whole host and one for each subset:

```sh
kubectl -n lb-demo get destinationrule httpbin -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
istioctl proxy-config cluster deploy/tester -n lb-demo | grep -E "httpbin|SERVICE"
```

```text
stable=stable
canary=canary
SERVICE FQDN                                                   PORT      SUBSET     DIRECTION     TYPE             DESTINATION RULE
httpbin.lb-demo.svc.cluster.local                              8000      -          outbound      EDS              httpbin.lb-demo
httpbin.lb-demo.svc.cluster.local                              8000      canary     outbound      EDS              httpbin.lb-demo
httpbin.lb-demo.svc.cluster.local                              8000      stable     outbound      EDS              httpbin.lb-demo
```

There are exactly two subsets, and the proxy holds a cluster for each.

---

## Item 2: Hash The `x-user` Header At Host Level

> **Task item 2:** A **host-level** `trafficPolicy` using **`consistentHash`** on the header **`x-user`**.

`consistentHash` makes the sending proxy calculate a hash from one value of the request, here the header `x-user`, and pick the endpoint from that hash. The same user then always reaches the same pod. Put the policy at the host level. That is `spec.trafficPolicy`, so it applies to every subset that does not override it. Edit `destinationrule-httpbin.yaml`:

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
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin configured
```

Check item 2. Print the host-level policy, and read the `lbPolicy` of each cluster in the proxy. `lbPolicy` is the load balancing algorithm of the cluster:

```sh
kubectl -n lb-demo get destinationrule httpbin -o jsonpath='{.spec.trafficPolicy}{"\n"}'
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local -o json | grep -E '"name": "outbound|lbPolicy'
```

```text
{"loadBalancer":{"consistentHash":{"httpHeaderName":"x-user"}}}
        "name": "outbound|8000||httpbin.lb-demo.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|canary|httpbin.lb-demo.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|stable|httpbin.lb-demo.svc.cluster.local",
        "lbPolicy": "RING_HASH",
```

All three clusters use `RING_HASH`, which is Envoy's name for `consistentHash`. Both subsets inherited the host policy. Item 3 changes that for `canary`. If a cluster still shows another policy, `istiod`, the Istio control plane, has not sent the change yet. Wait a few seconds and run the command again.

---

## Item 3: Override The Policy For `canary` Only

> **Task item 3:** A **subset-level** `trafficPolicy` on the **`canary`** subset only, using **`simple: ROUND_ROBIN`**, overriding the host-level policy for that subset.

Add a `trafficPolicy` inside the `canary` subset. Do not add one to `stable`. A field that a subset sets replaces the whole field of the host for that subset. A `loadBalancer` on `stable` would remove its session affinity. Edit `destinationrule-httpbin.yaml` into its final form:

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
destinationrule.networking.istio.io/httpbin configured
```

Check item 3. Print the policy of each subset:

```sh
kubectl -n lb-demo get destinationrule httpbin \
  -o jsonpath='{range .spec.subsets[*]}{.name}{" "}{.trafficPolicy}{"\n"}{end}'
```

```text
stable 
canary {"loadBalancer":{"simple":"ROUND_ROBIN"}}
```

Only `canary` has its own policy. `stable` has none, so it keeps the host policy.

---

## Item 4: Write The `VirtualService`

> **Task item 4:** A `VirtualService` named `httpbin` for host `httpbin` with two `http` rules, in this order:
>
> * requests carrying the header **`x-track: canary`** go to subset **`canary`**
> * everything else goes to subset **`stable`**

A `VirtualService` holds the routing rules for a host. The proxy reads the rules from top to bottom and uses the first rule that matches. A rule without `match` matches every request, so it comes last. Save this as `virtualservice-httpbin.yaml`:

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

```text
virtualservice.networking.istio.io/httpbin created
```

Check item 4. Let Istio check the objects, and print the rules in order:

```sh
istioctl analyze -n lb-demo
kubectl -n lb-demo get virtualservice httpbin \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.subset}{"\n"}{end}'
```

```text

✔ No validation issues found when analyzing namespace: lb-demo.
[{"headers":{"x-track":{"exact":"canary"}}}] -> canary
 -> stable
```

There are exactly two rules. The `x-track` rule comes first, and the rule without a match is last.

---

## Item 5: One User On `stable` Reaches One Pod

> **Task item 5:** Twelve requests carrying the same `x-user` value and no `x-track` header all reach **one single endpoint**, so the session affinity is real.

Send 12 requests as the same user, wait, and count the endpoints in the access log:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice"; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
  12 10.244.0.11:8080
```

All 12 requests reached one endpoint. The Start section showed the same loop spreading over four endpoints.

---

## Item 6: The `canary` Override Spreads The Same User

> **Task item 6:** Twelve requests carrying `x-track: canary` **and** the same `x-user` value reach **more than one endpoint**, because the subset policy overrides the host policy.

Send the same user again, but add the header that routes to `canary`:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get -H "x-user: alice" -H "x-track: canary"; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   6 10.244.0.10:8080
   6 10.244.0.13:8080
```

The requests spread over both `canary` pods, six each. The `x-user` value is the same as in item 5, but the behaviour is different, because the `canary` cluster uses round robin.

---

## Item 7: Requests With Nothing To Hash Spread

> **Task item 7:** Twelve requests with **no** `x-user` header and no `x-track` reach more than one endpoint, because a request with nothing to hash falls back to normal load balancing.

Send 12 requests without any header:

```sh
kubectl -n lb-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 12); do curl -s -o /dev/null http://httpbin:8000/get; done'
sleep 4
kubectl -n lb-demo logs deploy/tester -c istio-proxy --tail=12 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
   4 10.244.0.11:8080
   5 10.244.0.8:8080
   3 10.244.0.9:8080
```

The requests spread over three `stable` pods. The policy is the same `RING_HASH` as in item 5. These requests carry no `x-user` header, so the proxy has nothing to hash and uses normal load balancing. This is the usual cause of "session affinity works in my test but not in production".

---

## Item 8: The Two Clusters Have Different Policies

> **Task item 8:** The `tester` pod's proxy configuration (`istioctl proxy-config cluster`) shows **different `lbPolicy` values** for the `stable` and `canary` clusters.

Read the `lbPolicy` of each cluster again, now that the override is in place:

```sh
istioctl proxy-config cluster deploy/tester -n lb-demo \
  --fqdn httpbin.lb-demo.svc.cluster.local -o json | grep -E '"name": "outbound|lbPolicy'
```

```text
        "name": "outbound|8000||httpbin.lb-demo.svc.cluster.local",
        "lbPolicy": "RING_HASH",
        "name": "outbound|8000|canary|httpbin.lb-demo.svc.cluster.local",
        "name": "outbound|8000|stable|httpbin.lb-demo.svc.cluster.local",
        "lbPolicy": "RING_HASH",
```

The `stable` cluster shows `RING_HASH`. The `canary` cluster shows no `lbPolicy` line at all. Round robin is the default of Envoy, and the dump leaves default values out. So a missing `lbPolicy` means `ROUND_ROBIN`. The two values are different, as the task asks.

---

## Items 9 And 10: Nothing Else Changed

> **Task item 9:** Replica counts are unchanged: `httpbin-stable` still has 3 and `httpbin-canary` still has 2.
>
> **Task item 10:** The `httpbin` Service selector still selects on `app` only.

Run the Deployment and Service commands from the Start section again:

```sh
kubectl -n lb-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n lb-demo get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME             REPLICAS   UID
httpbin-canary   2          8c8b3e2b-c439-4408-83e8-91e5774ce6df
httpbin-stable   3          93fc2b79-d134-41af-ad78-b3aa9087166d
tester           1          7b0e3d1b-6e82-4f4a-883a-48dfb51a23c6
{"app":"httpbin"} 8000
```

The replica counts are 3 and 2, the `UID` values are the same, and the Service selects on `app` only.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-01
```

The grader sends real requests and reads the clusters in the proxy of `tester`.

---

## Mistakes That Fail The Grader

- **Putting `consistentHash` inside the `stable` subset instead of at host level (item 2).** It works for `stable`, but the task asks for the host-level policy.
- **Adding a `loadBalancer` to the `stable` subset (item 3).** A field that a subset sets replaces the whole field of the host, so `stable` would lose its `consistentHash`.
- **Setting `simple` and `consistentHash` in the same `loadBalancer` (items 2 and 3).** You can use only one of them, and Istio rejects the object.
- **Testing session affinity against one replica (items 5 to 7).** Every request reaches the same pod, whatever the policy.
- **Expecting session affinity for requests without the header (item 7).** The proxy spreads them, with no error.
- **Putting the rule without a `match` above the `x-track` rule (item 4).** The first matching rule wins, so the `canary` rule never runs.
- **Reading the access log too early (items 5 to 7).** The proxy writes the line a moment after the request. Wait a few seconds before you count.
