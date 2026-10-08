# Solution Walkthrough

One `VirtualService` carrying both of the section's features. The second rule does two things at once — splits caller traffic between two ship classes and copies every signal to a test ship — and keeping those two straight is the whole exercise.

---

## Step 1: Read the Starting State

```sh
kubectl -n checkout get pods --show-labels
kubectl -n checkout get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
kubectl -n checkout get destinationrule,virtualservice
```

```text
notification-service-v1-...   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-...   2/2   Running   app=notification-service,version=v2,...
notification-shadow-...       2/2   Running   app=notification-shadow,...
tester-...                    2/2   Running   app=tester,...
NAME                      REPLICAS
notification-service-v1   1
notification-service-v2   1
notification-shadow       1
tester                    1
No resources found in checkout namespace.
```

Note that `notification-shadow` is a **separate Service**, not a subset. It has no route to it and currently receives nothing:

```sh
kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | wc -l
```

```text
0
```

---

## Step 2: Define the Subsets

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > destinationrule-notification-service.yaml <<'EOF'
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
EOF
kubectl apply -f destinationrule-notification-service.yaml
```

The shadow needs no subset — it is a whole Service, addressed by host.

---

## Step 3: Both Rules, In Order

```sh
cat > virtualservice-notification.yaml <<'EOF'
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
      mirror:
        host: notification-shadow
      mirrorPercentage:
        value: 100.0
EOF
kubectl apply -f virtualservice-notification.yaml
istioctl analyze -n checkout
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: checkout.
```

Read the second rule's indentation carefully, because this is the capstone's real test:

- `route` holds **two** destinations whose weights sum to 100. That is the canary.
- `mirror` and `mirrorPercentage` are **siblings of `route`**, at the same indentation. The mirror is not a third destination and carries no weight.

Adding `notification-shadow` as a third route entry instead would make it a weighted destination — callers would start receiving shadow responses, and the grader rejects it explicitly.

Note also that the mirror is on the **second** rule only. Internal-tester traffic matches rule 1 and is not mirrored, because each `http` rule carries its own mirror settings. If the task had wanted internal traffic shadowed too, it would need its own `mirror` block.

---

## Step 4: Confirm the Proxy Holds Both Features

```sh
istioctl proxy-config routes deploy/tester -n checkout -o json | grep -cE 'weightedClusters|requestMirrorPolicies'
istioctl proxy-config routes deploy/tester -n checkout -o json | grep -A4 requestMirrorPolicies | head -6
```

```text
2
"requestMirrorPolicies": [
  {
    "cluster": "outbound|80||notification-shadow.checkout.svc.cluster.local",
```

Two features, one rule. The mirror cluster has empty subset pipes (`|80||`) because the shadow is addressed as a whole Service.

---

## Step 5: Verify Internal Testers Bypass the Split

```sh
for i in 1 2 3 4 5; do
  kubectl -n checkout exec deploy/tester -- \
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

Five for five. If any of these returned `["EMAIL"]`, the header rule is below the weighted rule and never runs.

---

## Step 6: Measure the Split and the Shadow Together

Baseline the shadow first, then send enough traffic for the proportion to mean something:

```sh
BEFORE=$(kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | grep -c -- -shadow)
kubectl -n checkout exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
sleep 3
AFTER=$(kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | grep -c -- -shadow)
echo "mirrored: $((AFTER - BEFORE)) of 200"
```

```text
  158 ["EMAIL"]
   42 ["EMAIL","SMS"]
mirrored: 200 of 200
```

158 of 200 is 79% — a correct 80/20 split, and the grader accepts 65–92% because each request is an independent draw. Every one of the 200 was also copied to the shadow, which is what `mirrorPercentage: 100` on the same rule buys you.

Confirm the copies carry the rewritten authority:

```sh
kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=2 | grep -i shadow
```

```text
[2026-09-27T14:02:55.118Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 16 1 1 "-" "curl/8.5.0" "..." "notification-shadow-shadow" "10.244.0.22:8084" ...
```

The doubled `-shadow` looks odd and is correct: the host is already named `notification-shadow`, and Istio appends its own suffix to the authority of every copy.

---

## Step 7: Confirm Nothing Was Scaled

```sh
kubectl -n checkout get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
```

```text
notification-service-v1   1
notification-service-v2   1
notification-shadow       1
tester                    1
```

---

## Common Mistakes

- **The shadow added as a third route destination.** It becomes a weighted destination, callers see its responses, and the weights no longer sum correctly either.
- **`mirror` indented inside the route list.** It is a sibling of `route` on the same rule.
- **The mirror on the wrong rule.** Each `http` rule has its own mirror settings; on rule 1 it would shadow only internal testers.
- **Header rule below the weighted rule.** The catch-all matches everything, so the header rule never runs.
- **Measuring the split with 10 requests.** Independent per-request draws; use 200.
- **Counting shadow log lines without a baseline.** Take a `BEFORE` count and subtract.
- **Scaling Deployments to shape the split.** Weights are applied before endpoint selection, so it would not work anyway — and the grader checks.
