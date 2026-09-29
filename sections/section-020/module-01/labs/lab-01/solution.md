# Solution Walkthrough

Two objects, and the ordering of the two `http` rules is as graded as the weights themselves.

---

## Step 1: Read the Starting State

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

One replica each — note that, because the grader checks it has not changed. Baseline traffic hits both versions with no configuration at all:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  11 ["EMAIL"]
   9 ["EMAIL","SMS"]
```

That is kube-proxy round robin, not a weight. It only looks similar to a 50/50 split.

---

## Step 2: Define the Subsets

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-notification-service.yaml <<'EOF'
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
EOF
kubectl apply -f destinationrule-notification-service.yaml
```

```text
destinationrule.networking.istio.io/notification-service created
```

---

## Step 3: Write Both Rules, In Order

The header rule goes **first**. Evaluation is top down and stops at the first match, so a rule placed after the catch-all weighted rule would never run.

```sh
cat > virtualservice-notification.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification created
```

Three things the grader looks at specifically:

- **`exact: "true"` is quoted.** Unquoted `true` is a YAML boolean and the apply is rejected.
- **`weight` sits beside `destination`, not inside it.** Both destinations are in **one** route block; two separate `http` rules each at 100 would not split anything, because the first would match everything.
- **The weighted rule has no `match` block.** It is the catch-all, and it has to be last.

The weights sum to 100 within their own route block. Try `70` and `40` and the admission webhook refuses it with a message naming the total — worth doing once so you recognise the error.

---

## Step 4: Confirm the Proxy Holds the Weights

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

If this block is missing, the [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) never reached the sidecar and no amount of re-reading the YAML will help — check the namespace and `istioctl proxy-status`.

---

## Step 5: Verify Both Behaviours

The header rule must be absolute, not probabilistic. Five samples is enough because any `["EMAIL"]` here is a failure:

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

Now the split, over enough requests to mean something. Ten would tell you nothing:

```sh
kubectl -n shifting-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  143 ["EMAIL"]
   57 ["EMAIL","SMS"]
```

143 of 200 is about 72% — a correct 70/30 split. Your numbers will differ by a few percent, and running it again will give a different pair. The grader accepts 55–85% for exactly this reason.

---

## Step 6: Confirm You Did Not Cheat With Replicas

```sh
kubectl -n shifting-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
```

```text
notification-service-v1   1
notification-service-v2   1
```

Scaling `v1` to 7 and `v2` to 3 would not produce a 70/30 split anyway — the weighted choice happens before endpoint load balancing, so the pod count never enters into it. Prove that to yourself in the playground by scaling `v1` to 4 at a 50/50 split and watching the share stay at 50%.

---

## Common Mistakes

- **Header rule below the weighted rule.** The weighted rule has no `match`, so it matches everything; the header rule never runs.
- **Two separate `http` rules instead of one route block.** The first matches everything and nothing is split.
- **`weight` nested inside `destination`.** Schema error — it belongs beside it.
- **Weights that do not sum to 100.** Rejected at admission with the total in the message.
- **Measuring with 10 requests.** Each request is an independent draw; small samples are meaningless.
- **Scaling Deployments to move traffic.** Replica count is capacity, not share — and the grader checks it.
- **Patching `spec.http` expecting an element edit.** A merge patch replaces the whole list.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [DestinationRule API](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `host`, `subsets`, and the `trafficPolicy` block
- [Subsets and traffic policy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#Subset) — how a subset name maps to pod labels
- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key: `headers`, `uri`, `queryParams`, `method`, `withoutHeaders`
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice and what each means
- [HTTPRouteDestination API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRouteDestination) — `destination` plus `weight`, and the rule that weights sum to 100
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
- [Istio analyzer messages](https://istio.io/latest/docs/reference/config/analysis/) — every `IST####` code and what triggers it
