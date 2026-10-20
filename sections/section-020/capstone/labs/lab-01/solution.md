# Solution Walkthrough

One `VirtualService` carries both features of traffic shifting in this task. The second rule does two jobs at once: it splits client requests between two subsets, and it copies every request to a separate shadow Service. Keeping the two jobs apart in the YAML is the whole task. The walkthrough builds the file in two steps. Items 2, 3 and 4 give the two rules and the split. Item 5 adds the mirror. Items 6 to 12 prove the result.

---

## Start: Read The Starting State

The task describes four Deployments with one replica each, a separate shadow Service, and no Istio routing. Check that this is true:

```sh
kubectl -n checkout get pods -L app,version
kubectl -n checkout get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n checkout get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
kubectl -n checkout get destinationrule,virtualservice
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE   APP                    VERSION
notification-service-v1-54dd46d4b6-4xrsl   2/2     Running   0          5s    notification-service   v1
notification-service-v2-d79d6dcc4-hv4lf    2/2     Running   0          5s    notification-service   v2
notification-shadow-57fb6c8ff9-9gtgs       2/2     Running   0          5s    notification-shadow    
tester-69699fd775-c8djl                    2/2     Running   0          5s    tester                 
NAME                      REPLICAS   UID
notification-service-v1   1          200153e3-7982-4196-9f1c-528af2f46a34
notification-service-v2   1          3de9967b-92ff-464c-9919-4fe1ed12459d
notification-shadow       1          139ec32a-1c0f-4b30-9945-5d9bfc5c01aa
tester                    1          6136d323-c24e-4c46-9cfc-fc24b65e9876
NAME                   PORT   SELECTOR
notification-service   80     map[app:notification-service]
notification-shadow    80     map[app:notification-shadow]
No resources found in checkout namespace.
```

`notification-shadow` is a separate Service, not a subset of `notification-service`. Nothing routes to it, so its sidecar proxy has logged no requests. The sidecar proxy is the Envoy container that Istio adds to each pod. Count the `POST /notify` lines in its access log. Wait a few seconds first, because the proxy writes a log line a moment after the request:

```sh
sleep 5
kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | grep -c 'POST /notify'
```

```text
0
```

The `UID` values above are the identity of the Deployments. Items 11 and 12 compare against them.

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `notification-service` that defines two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

A `DestinationRule` holds the policies for traffic to one host, and it defines subsets. A subset is a named group of pods, selected by labels. Both rules of the `VirtualService` send requests to subsets, so create the `DestinationRule` first. Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: checkout
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-notification-service.yaml
```

```text
destinationrule.networking.istio.io/notification-service created
```

Check item 1:

```sh
kubectl -n checkout get destinationrule notification-service \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
v1=v1
v2=v2
```

The shadow needs no subset. It is a whole Service, and the mirror names it by host.

---

## Items 2, 3 And 4: Write The Two Rules And The 80/20 Split

> **Task item 2:** The **first** `http` rule matches the header **`x-internal: true`** (exact match) and sends those requests to subset **`v2`**. Internal testers always get the canary, whatever the weights are.
>
> **Task item 3:** The **second** `http` rule is the catch-all rule: it has no `match` block.
>
> **Task item 4:** It splits client requests **80% to `v1`** and **20% to `v2`** in a single `route` list.

A `VirtualService` holds the routing rules for a host. The proxy reads the rules from top to bottom and uses the first rule that matches. A rule without `match` matches every request, so it must be last. Both destinations of the split go in one `route` list, with a `weight` next to each `destination`.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: checkout
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            x-internal:
              exact: "true"
      route:
        - destination:
            host: notification-service
            subset: v2
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 80
        - destination:
            host: notification-service
            subset: v2
          weight: 20
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification created
```

Check items 2, 3 and 4. Let Istio check the objects, and print each rule with its match and its weighted destinations:

```sh
istioctl analyze -n checkout
kubectl -n checkout get virtualservice notification \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{range .route[*]}{.destination.subset}{":"}{.weight}{" "}{end}{"\n"}{end}'
```

```text

✔ No validation issues found when analyzing namespace: checkout.
[{"headers":{"x-internal":{"exact":"true"}}}] -> v2: 
 -> v1:80 v2:20 
```

There are exactly two rules. The first matches the header and sends to `v2`. The second has an empty match, which is the catch-all, and it lists `v1` with weight 80 and `v2` with weight 20 in one route list. Because the mirror is not in the file yet, the shadow still gets nothing. Count again with the command from the Start section, and the result is still `0`.

---

## Item 5: Mirror The Second Rule To `notification-shadow`

> **Task item 5:** The **same rule** mirrors its requests to the separate host **`notification-shadow`**, with `mirrorPercentage` set explicitly to **100**.

Mirroring means that the proxy of the client sends a copy of each request to a second destination and throws away the response of the copy. Add `mirror` and `mirrorPercentage` to the second rule. They are siblings of `route`, at the same indentation. Each `http` rule has its own mirror settings, so the mirror on the second rule copies only ordinary requests. Edit `virtualservice-notification.yaml`, so that the second rule looks like this:

```yaml
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 80
        - destination:
            host: notification-service
            subset: v2
          weight: 20
      mirror:
        host: notification-shadow
      mirrorPercentage:
        value: 100.0
```

Apply the file again:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification configured
```

Check item 5:

```sh
kubectl -n checkout get virtualservice notification -o jsonpath='{.spec.http[1].mirror} {.spec.http[1].mirrorPercentage}{"\n"}'
```

```text
{"host":"notification-shadow"} {"value":100}
```

The second rule mirrors to the host `notification-shadow` at 100%.

---

## Item 6: The Shadow Is A Mirror, Not A Destination

> **Task item 6:** The mirror must be a mirror, not a third weighted destination: `notification-shadow` must not appear in any `route`, so no client response ever comes from it.

Print the destination hosts of every rule:

```sh
kubectl -n checkout get virtualservice notification \
  -o jsonpath='{range .spec.http[*]}{range .route[*]}{.destination.host}{" "}{end}{"\n"}{end}'
```

```text
notification-service 
notification-service notification-service 
```

Every destination in every `route` is `notification-service`. The shadow appears only in `mirror`. If you add the shadow as a third entry in the `route` list, it becomes a weighted destination, clients start to get its responses, and the grader rejects it.

---

## Item 7: The Proxy Holds Both Features

> **Task item 7:** The proxy of the `tester` pod holds both `weightedClusters` and `requestMirrorPolicies`.

The proxy of the client makes the routing decision and sends the copy. So both features must be in its route table. `istiod`, the Istio control plane, sends the change to the proxy. Wait a few seconds, then count the two keys, and print the mirror policy:

```sh
istioctl proxy-config routes deploy/tester -n checkout -o json | grep -cE 'weightedClusters|requestMirrorPolicies'
istioctl proxy-config routes deploy/tester -n checkout -o json | grep -A4 requestMirrorPolicies | head -6
```

```text
2
                            "requestMirrorPolicies": [
                                {
                                    "cluster": "outbound|80||notification-shadow.checkout.svc.cluster.local",
                                    "runtimeFraction": {
                                        "defaultValue": {
```

`weightedClusters` holds the 80/20 split, and `requestMirrorPolicies` holds the mirror. The mirror cluster name has an empty subset field (`|80||`), because the mirror names the shadow as a whole Service.

---

## Item 8: Internal Testers Always Reach `v2`

> **Task item 8:** Five requests with `x-internal: true` all reach `v2`. Those requests are not part of the split.

```sh
for i in 1 2 3 4 5; do
  kubectl -n checkout exec deploy/tester -- \
    curl -s -X POST -H "x-internal: true" http://notification-service/notify
  echo
done
```

```text
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
```

All five requests reached `v2`, which answers `["EMAIL","SMS"]`. If one of them answered `["EMAIL"]`, the header rule would be below the catch-all rule.

---

## Items 9 And 10: Measure The Split And The Mirror Together

> **Task item 9:** Over 200 ordinary requests, the share of `v1` is between 65% and 92%. An all-v1 or all-v2 result fails.
>
> **Task item 10:** `notification-shadow` receives a copy of almost every ordinary request: the grader counts at least 150 new lines for the 200 requests in the access log of the `notification-shadow` sidecar proxy.

The proxy picks a destination for each request at random, so a small sample tells you nothing. Send 200 requests. Count the shadow log lines before and after, because the log may hold lines from earlier runs, and wait before each count:

```sh
sleep 5
BEFORE=$(kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | grep -c 'POST /notify')
kubectl -n checkout exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
sleep 5
AFTER=$(kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | grep -c 'POST /notify')
echo "mirrored: $((AFTER - BEFORE)) of 200"
```

```text
  45 ["EMAIL","SMS"]
 155 ["EMAIL"]
mirrored: 200 of 200
```

For item 9: 155 of 200 requests reached `v1`. That is 77.5%, which is inside the range of 65% to 92%. For item 10: all 200 requests were copied to the shadow. This is what `mirrorPercentage: 100` on the same rule does. The client responses came only from `v1` and `v2`.

---

## Items 11 And 12: Nothing Else Changed

> **Task item 11:** No replica count has changed: all four Deployments still run exactly 1 replica. Traffic share is a weight, not a pod count.
>
> **Task item 12:** The `notification-service` Service still selects on `app` only, and no Deployment was added or removed.

Run the Deployment and Service commands from the Start section again:

```sh
kubectl -n checkout get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n checkout get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
NAME                      REPLICAS   UID
notification-service-v1   1          200153e3-7982-4196-9f1c-528af2f46a34
notification-service-v2   1          3de9967b-92ff-464c-9919-4fe1ed12459d
notification-shadow       1          139ec32a-1c0f-4b30-9945-5d9bfc5c01aa
tester                    1          6136d323-c24e-4c46-9cfc-fc24b65e9876
NAME                   PORT   SELECTOR
notification-service   80     map[app:notification-service]
notification-shadow    80     map[app:notification-shadow]
```

The output is the same as before. The same four Deployments exist with one replica each and the same `UID` values, and the Service still selects on `app` only.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-020/capstone/labs/lab-01
```

The grader checks the route table of the `tester` proxy, the split, and the copies in the access log of the shadow.

---

## Mistakes That Fail The Grader

- **The shadow added as a third `route` destination (items 5 and 6).** It becomes a weighted destination, and clients get its responses.
- **`mirror` indented inside the `route` list (item 5).** It is a sibling of `route` on the same rule.
- **The mirror on the wrong rule (item 5).** On the first rule, the mirror would copy only the requests of the internal testers.
- **The header rule below the catch-all rule (items 2 and 3).** The catch-all rule matches every request, so the header rule never runs.
- **Measuring the split with 10 requests (item 9).** The proxy picks a destination for each request at random. Use 200.
- **Counting the shadow log lines without a baseline (item 10).** Take a count before the test and subtract it.
- **Scaling Deployments to shape the split (item 11).** The proxy applies the weights before it picks a pod, so replica counts do not change the split.
