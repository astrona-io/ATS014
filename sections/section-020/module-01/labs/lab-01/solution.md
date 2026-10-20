# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. Item 1 creates the `DestinationRule`. Items 2 and 3 describe the two rules of one `VirtualService`, so you write the file in item 2 and check the weights in item 3. Items 4 to 7 prove the behaviour and prove that you changed nothing else.

---

## Start: Read The Starting State

The task describes two versions of one application with one replica each, and no Istio routing objects. Check that this is true:

```sh
kubectl -n shifting-demo get pods -L app,version
kubectl -n shifting-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n shifting-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n shifting-demo get destinationrule,virtualservice
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE   APP                    VERSION
notification-service-v1-54dd46d4b6-ztsk2   2/2     Running   0          6s    notification-service   v1
notification-service-v2-d79d6dcc4-cc4zz    2/2     Running   0          6s    notification-service   v2
tester-69699fd775-ngs6k                    2/2     Running   0          6s    tester                 
NAME                      REPLICAS   UID
notification-service-v1   1          1a10c19e-cc0a-4409-b294-d9980df323b7
notification-service-v2   1          785a6e16-9ac7-4b21-be91-507c6b041808
tester                    1          8461eaf2-d81b-45df-9aac-0ab037c43be1
{"app":"notification-service"}
No resources found in shifting-demo namespace.
```

Each version runs one replica, and the Service selects on `app` only. Without any Istio configuration, requests already reach both versions. Prove it with 20 requests from the `tester` pod:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
   7 ["EMAIL","SMS"]
  13 ["EMAIL"]
```

`kube-proxy`, the Kubernetes component that forwards Service traffic, spreads the connections over the pods. That is not a weight. It only looks like a split. Items 6 and 7 compare against the replica counts and the `UID` values above.

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `notification-service` with exactly two subsets, **`v1`** and **`v2`**, each selecting pods on the **`version`** label.

A `DestinationRule` holds the policies for traffic to one host, and it defines subsets. A subset is a named group of pods, selected by a label. Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: shifting-demo
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
kubectl -n shifting-demo get destinationrule notification-service \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
v1=v1
v2=v2
```

There are exactly two subsets, and each selects its own `version` label.

---

## Item 2: Write Both Rules In The Right Order

> **Task item 2:** A `VirtualService` named `notification` for the host `notification-service`, with **two** `http` rules in this order:
>
> * **First**, a rule that matches the header **`x-internal: true`** and sends those requests to subset **`v2`**. Internal testers always get the new version, whatever the canary share is.
> * **Second**, a weighted rule with no `match` that splits all other requests **70% to `v1`** and **30% to `v2`**.

A `VirtualService` tells the sidecar proxies where to send requests for a host. A sidecar proxy is the Envoy container that Istio adds to each pod. The proxy reads the `http` rules from top to bottom and uses the first rule that matches. The weighted rule has no `match`, so it matches every request. A rule placed after it would never run. So the header rule goes first.

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: shifting-demo
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
          weight: 70
        - destination:
            host: notification-service
            subset: v2
          weight: 30
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification created
```

Quote `"true"`. Without the quotes, YAML reads `true` as a boolean, and Kubernetes rejects the apply.

Check item 2. Let Istio check the objects, and print the two rules in order:

```sh
istioctl analyze -n shifting-demo
kubectl -n shifting-demo get virtualservice notification \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[*].destination.subset}{"\n"}{end}'
```

```text

✔ No validation issues found when analyzing namespace: shifting-demo.
[{"headers":{"x-internal":{"exact":"true"}}}] -> v2
 -> v1 v2
```

There are exactly two rules. The first matches the header and sends to `v2`. The second has no `match` and lists both subsets.

---

## Item 3: One Route List With The Weights 70 And 30

> **Task item 3:** The weighted rule must be a single route list with two destinations that carry `weight: 70` and `weight: 30`.

`weight` sits next to `destination`, not inside it. Both destinations belong to one route list. Two separate `http` rules with a weight of 100 each would not split anything, because the first one matches every request. Check the object, and then check what the proxy of the `tester` pod really holds:

```sh
kubectl -n shifting-demo get virtualservice notification \
  -o jsonpath='{range .spec.http[1].route[*]}{.destination.subset}{" weight="}{.weight}{"\n"}{end}'
istioctl proxy-config routes deploy/tester -n shifting-demo -o json | grep -A12 weightedClusters | head -16
```

```text
v1 weight=70
v2 weight=30
                            "weightedClusters": {
                                "clusters": [
                                    {
                                        "name": "outbound|80|v1|notification-service.shifting-demo.svc.cluster.local",
                                        "weight": 70
                                    },
                                    {
                                        "name": "outbound|80|v2|notification-service.shifting-demo.svc.cluster.local",
                                        "weight": 30
                                    }
                                ]
                            },
                            "timeout": "0s",
```

The second rule has one route list with the weights 70 and 30. The proxy holds a `weightedClusters` block with the same weights. Each subset is its own Envoy cluster, which is a named destination. If the block is missing, the `VirtualService` has not reached the proxy. Run `istioctl proxy-status` to see whether the proxy is in sync with `istiod`, the Istio control plane, and wait a few seconds.

The weights add up to 100, so the numbers read as percentages. Istio 1.30.5 does not reject a total other than 100. It uses the numbers as a ratio. The grader expects exactly `70` and `30`.

---

## Item 4: Internal Testers Always Reach `v2`

> **Task item 4:** A request with the header `x-internal: true` must reach `v2` every time. It must not be part of the split.

Send five requests with the header. Any `["EMAIL"]` in the output is a failure:

```sh
for i in 1 2 3 4 5; do
  kubectl -n shifting-demo exec deploy/tester -- \
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

All five requests reached `v2`, which answers `["EMAIL","SMS"]`.

---

## Item 5: Ordinary Requests Are Split About 70/30

> **Task item 5:** Ordinary requests must reach **both** versions, in roughly the configured shares. The grader sends 200 requests and accepts 55–85% for `v1`, so an all-`v1` or all-`v2` result fails.

The proxy makes a separate random pick for each request, so a small sample tells you nothing. Send 200 requests:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  55 ["EMAIL","SMS"]
 145 ["EMAIL"]
```

145 of 200 requests reached `v1`. That is 72.5%, which fits a 70/30 split. Your numbers will differ by a few percent on each run, and that is why the grader accepts 55 to 85%.

---

## Item 6: The Replica Counts Did Not Change

> **Task item 6:** Do **not** change the replica count of either Deployment. The traffic share is set by a weight, not by a pod count, and the grader checks that both Deployments still run exactly 1 replica.

```sh
kubectl -n shifting-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
```

```text
NAME                      REPLICAS   UID
notification-service-v1   1          1a10c19e-cc0a-4409-b294-d9980df323b7
notification-service-v2   1          785a6e16-9ac7-4b21-be91-507c6b041808
tester                    1          8461eaf2-d81b-45df-9aac-0ab037c43be1
```

Both versions still run one replica, with the same `UID` values as before. Scaling `v1` to 7 pods and `v2` to 3 pods would not give a 70/30 split anyway. The proxy picks a subset by weight first, and only then picks a pod inside that subset. So the number of pods never changes the share.

---

## Item 7: The Service And The Workloads Are Unchanged

> **Task item 7:** Do not change the Service selector, and do not add a third Deployment.

```sh
kubectl -n shifting-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
```

```text
{"app":"notification-service"}
```

The Service still selects on `app` only, and the Deployment list in item 6 shows the same three Deployments as at the start.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-020/module-01/labs/lab-01
```

The grader also reads the weighted clusters in the proxy of the `tester` pod, so the split must reach the proxy.

---

## Mistakes That Fail The Grader

- **The header rule below the weighted rule (item 2).** The weighted rule matches every request, so the header rule never runs.
- **Two separate `http` rules instead of one route list (item 3).** The first rule matches every request, and nothing is split.
- **`weight` inside `destination` (item 3).** Kubernetes rejects it. It belongs next to `destination`.
- **Weights that do not add up to 100 (item 3).** Istio 1.30.5 accepts them and uses them as a ratio, but the grader expects exactly `70` and `30`.
- **Measuring with 10 requests (item 5).** Each request gets its own random pick, so a small sample means nothing.
- **Scaling Deployments to move traffic (item 6).** The replica count sets capacity, not share, and the grader checks it.
- **Patching `spec.http` to change one item (item 2).** A merge patch replaces the whole list, so it must restate every rule.
