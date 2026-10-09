# Solution Walkthrough

The lab needs two objects: a `DestinationRule` that defines the subsets, and a `VirtualService` that routes to them. The grader checks the order of the two `http` rules as closely as the weights. The rule for internal testers must come before the rule that splits all other requests.

---

## Step 1: Read The Starting State

List the pods with their labels, the replica count of each Deployment, and any Istio routing objects:

```sh
kubectl -n shifting-demo get pods --show-labels
kubectl -n shifting-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
kubectl -n shifting-demo get destinationrule,virtualservice
```

```text
notification-service-v1-5b9c7d8f4-2ktzn   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-7f8d6c5b9-lq4wm   2/2   Running   app=notification-service,version=v2,...
tester-6d4f8b7c5-9xnpk                    2/2   Running   app=tester,...
NAME                      REPLICAS
notification-service-v1   1
notification-service-v2   1
tester                    1
No resources found in shifting-demo namespace.
```

Each version runs one replica. Remember this, because the grader checks that it has not changed. Without any Istio configuration, requests already reach both versions:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  11 ["EMAIL"]
   9 ["EMAIL","SMS"]
```

This is kube-proxy, the Kubernetes component that forwards Service traffic, spreading connections over the pods. It is not a weight. It only looks similar to a 50/50 split.

---

## Step 2: Define The Subsets

A `DestinationRule` defines **subsets**: named groups of a Service's pods, selected by a label. Write the manifest to a file and apply the file. This habit helps in the exam: you can read the file again, edit it and apply it again.

Save this as `destinationrule-notification-service.yaml`:

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

---

## Step 3: Write Both Rules In Order

A `VirtualService` tells the sidecar proxies where to send requests for a host. The header rule goes **first**. The proxy checks the `http` rules from the top and stops at the first match. The weighted rule has no `match`, so it matches every request, and a rule placed after it would never run.

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

The grader checks three details in particular:

- **`exact: "true"` is quoted.** Without quotes, `true` is a YAML boolean, and Kubernetes rejects the apply.
- **`weight` sits next to `destination`, not inside it.** Both destinations are in **one** route list. Two separate `http` rules, each at 100, would not split anything, because the first one would match every request.
- **The weighted rule has no `match` block.** It matches every request that reaches it, so it has to be last.

The weights add up to 100 inside their own route list. Keep them that way, so the numbers read as percentages. On Istio 1.30.5 a total that is not 100 (for example `70` and `40`) is **not** rejected. The proxy uses the numbers as a ratio, so the split still works, but the numbers no longer read as percentages. The grader expects exactly `70` and `30`.

---

## Step 4: Confirm The Proxy Holds The Weights

```sh
istioctl analyze -n shifting-demo
istioctl proxy-config routes deploy/tester -n shifting-demo -o json | grep -A12 weightedClusters | head -16
```

```text
✔ No validation issues found when analyzing namespace: shifting-demo.
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
```

`istioctl analyze` checks your Istio objects for known problems. `istioctl proxy-config routes` prints the route table that the `tester` sidecar proxy really uses. Each subset is its own Envoy **cluster** (a named destination), and the `weightedClusters` block lists each cluster with its weight. If this block is missing, the `VirtualService` never reached the sidecar proxy, and reading the YAML again will not help. Check the namespace, and run `istioctl proxy-status` to see whether the proxy is in sync with `istiod`.

---

## Step 5: Check Both Behaviours

The header rule must send every tester request to `v2`, not just most of them. Five requests are enough, because any `["EMAIL"]` here is a failure:

```sh
for i in 1 2 3 4 5; do
  kubectl -n shifting-demo exec deploy/tester -- \
    curl -s -X POST -H "x-internal: true" http://notification-service/notify
done
```

```text
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
```

Now check the split, over enough requests to mean something. The proxy makes a separate random pick for each request, so ten requests would tell you nothing:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  143 ["EMAIL"]
   57 ["EMAIL","SMS"]
```

143 of 200 is about 72%, which is a correct 70/30 split. Your numbers will differ by a few percent, and each run gives a different pair. That is why the grader accepts 55–85% for `v1`.

---

## Step 6: Confirm The Replica Counts Did Not Change

```sh
kubectl -n shifting-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
```

```text
notification-service-v1   1
notification-service-v2   1
```

Scaling `v1` to 7 and `v2` to 3 would not produce a 70/30 split anyway. The proxy makes the weighted pick between subsets first, and only then uses load balancing to pick a pod inside the chosen subset. So the pod count never changes the share. For example, with four `v1` pods and one `v2` pod at a 50/50 split, each version still gets about 50% of the requests.

---

## Common mistakes

- **Header rule below the weighted rule.** The weighted rule has no `match`, so it matches every request, and the header rule never runs.
- **Two separate `http` rules instead of one route list.** The first rule matches every request, and nothing is split.
- **`weight` inside `destination`.** Kubernetes rejects it with a schema error. It belongs next to `destination`.
- **Weights that do not add up to 100.** Istio 1.30.5 accepts them and uses them as a ratio, so the split looks wrong when you read it as percentages. The grader checks for exactly `70` and `30`.
- **Measuring with 10 requests.** Each request gets its own random pick, so a small sample means nothing.
- **Scaling Deployments to move traffic.** The replica count sets capacity, not share, and the grader checks it.
- **Patching `spec.http` to change one item.** A merge patch replaces the whole list, so it must restate every rule.
