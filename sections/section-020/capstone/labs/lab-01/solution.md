# Solution Walkthrough

One `VirtualService` carries both features of traffic shifting. The second rule does two jobs at once: it splits client requests between two subsets, and it copies every request to a separate shadow Service. Keeping those two jobs apart in the YAML is the whole task.

---

## Step 1: Read the starting state

List the pods with their labels, the replica count of each Deployment, and the Istio routing objects:

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

`notification-shadow` is a **separate Service**, not a subset of `notification-service`. Nothing routes to it, so its sidecar proxy has logged no requests yet:

```sh
kubectl -n checkout logs -l app=notification-shadow -c istio-proxy --tail=-1 | wc -l
```

```text
0
```

---

## Step 2: Define the subsets

A subset is a named group of a Service's pods, selected by labels. Both rules of the `VirtualService` send requests to subsets, so the `DestinationRule` comes first.

Save this as `destinationrule-notification-service.yaml`:

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

The shadow needs no subset. It is a whole Service, and the mirror names it by host.

---

## Step 3: Write both rules, in order

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
      mirror:
        host: notification-shadow
      mirrorPercentage:
        value: 100.0
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result:

```sh
istioctl analyze -n checkout
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: checkout.
```

Read the indentation of the second rule carefully, because this is the real test:

- `route` holds **two** destinations whose weights add up to 100. That is the canary split.
- `mirror` and `mirrorPercentage` are **siblings of `route`**, at the same indentation. The mirror is not a third destination and has no weight.

If you add `notification-shadow` as a third `route` entry instead, it becomes a weighted destination. Clients then start to get responses from the shadow, and the grader rejects it.

The mirror is on the **second** rule only. Requests from internal testers match rule 1, so the proxy does not copy them, because each `http` rule has its own mirror settings. If the task wanted internal traffic copied too, rule 1 would need its own `mirror`.

---

## Step 4: Check that the proxy holds both features

The sidecar proxy of the client makes the routing decision and sends the copy, so both features must be in the route table of the `tester` proxy:

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

`weightedClusters` holds the 80/20 split and `requestMirrorPolicies` holds the mirror. The mirror cluster name has an empty subset field (`|80||`) because the mirror names the shadow as a whole Service, with no subset.

---

## Step 5: Check that internal testers skip the split

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

Five out of five reached `v2`. If any of these returned `["EMAIL"]`, the header rule is below the catch-all rule. The proxy uses the first rule that matches, so a rule below the catch-all never runs.

---

## Step 6: Measure the split and the mirror together

Count the lines in the shadow's access log before and after the test, because the log may hold lines from earlier runs. Then send 200 requests, enough for the share to mean something:

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

158 of 200 is 79%, a correct 80/20 split. The proxy picks a destination for each request on its own, at random, so the grader accepts 65% to 92%. All 200 requests were also copied to the shadow, which is what `mirrorPercentage: 100` on the same rule does.

The `grep -c -- -shadow` counts the lines that contain the text `-shadow`. On Istio 1.30 that text does not come from the host name of the copy. Istio 1.30 sends the copy unchanged, so its authority (the host name the request was sent to) stays `notification-service`. Older Istio releases added a `-shadow` suffix to it, but 1.30 does not. The text matches because each inbound line in the shadow's access log ends with the server name of the mTLS (mutual TLS) connection the copy arrived on, `outbound_.80_._.notification-shadow.checkout.svc.cluster.local`, and that name contains `notification-shadow`. The grader counts the lines the same way.

---

## Step 7: Check that nothing was scaled

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

## Common mistakes

- **The shadow added as a third `route` destination.** It becomes a weighted destination, clients get its responses, and the weights no longer add up as intended.
- **`mirror` indented inside the `route` list.** It is a sibling of `route` on the same rule.
- **The mirror on the wrong rule.** Each `http` rule has its own mirror settings. On rule 1, the mirror would copy only the internal testers' requests.
- **The header rule below the catch-all rule.** The catch-all rule matches every request, so the header rule never runs.
- **Measuring the split with 10 requests.** The proxy picks a destination for each request at random. Use 200.
- **Counting the shadow's log lines without a baseline.** Take a `BEFORE` count and subtract it.
- **Scaling Deployments to shape the split.** The proxy applies the weights before it picks a pod, so replica counts do not change the split. The grader also checks that every Deployment still runs 1 replica.
