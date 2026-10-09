# Solution Walkthrough

You create two objects, in this order: first the `DestinationRule`, so the subset names exist, then the `VirtualService` that uses them. The grader cares most about the last check: proof that the rule order leaves every rule reachable.

---

## Step 1: Read the Starting State

Confirm what you have before you change anything. The exam rewards this habit.

```sh
kubectl -n routing-demo get pods --show-labels
kubectl -n routing-demo get svc notification-service -o yaml | grep -A4 selector
kubectl -n routing-demo get destinationrule,virtualservice
```

```text
notification-service-v1-7d4c9b6f8d-x2mkq   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-6f8b7c5d94-lq7rn   2/2   Running   app=notification-service,version=v2,...
tester-5c7d8f9b6c-8vzpl                    2/2   Running   app=tester,...
  selector:
    app: notification-service
No resources found in routing-demo namespace.
```

The output shows three facts. The pods carry a `version` label, the Service ignores it on purpose, and no Istio routing exists yet.

Now take a baseline. Both versions answer, in no fixed pattern:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  11 ["EMAIL"]
   9 ["EMAIL","SMS"]
```

---

## Step 2: Define the Subsets

A `DestinationRule` defines subsets: named groups of pods, picked by pod labels. Write the manifest to a file and apply the file. You can then read it again, edit it and apply it again.

Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: routing-demo
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

Then check the result. Look at the clusters `istiod` built in the proxy of `tester`, and confirm that each subset selects a pod. A subset whose labels match no pod is valid configuration, and gives a `503` later:

```sh
istioctl proxy-config cluster deploy/tester -n routing-demo | grep notification
```

```text
notification-service.routing-demo.svc.cluster.local   80   -    outbound   EDS
notification-service.routing-demo.svc.cluster.local   80   v1   outbound   EDS
notification-service.routing-demo.svc.cluster.local   80   v2   outbound   EDS
```

Run the baseline loop again and the split is unchanged. That is correct: a `DestinationRule` only names the subsets. It does not route any request.

---

## Step 3: Write the VirtualService With The Specific Rules First

A `VirtualService` sets where requests to a host go. The three match rules go above the default rule. Envoy, the sidecar proxy, checks the rules from the top and stops at the first match. So a rule with no `match` block must be last.

Save this as `virtualservice-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification-service
  namespace: routing-demo
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            testing:
              exact: "true"
      route:
        - destination:
            host: notification-service
            subset: v2
    - match:
        - uri:
            prefix: /notify/beta
      route:
        - destination:
            host: notification-service
            subset: v2
    - match:
        - queryParams:
            version:
              exact: "2"
      route:
        - destination:
            host: notification-service
            subset: v2
    - route:
        - destination:
            host: notification-service
            subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

```text
virtualservice.networking.istio.io/notification-service created
```

Three details each fail the task if you get them wrong:

- **`exact: "true"` is quoted.** Unquoted `true` is a YAML boolean and the apply is rejected. The same applies to `exact: "2"`.
- **The query rule uses `queryParams`, not `uri`.** The `uri` value stops at the `?`, so `uri: { exact: "/notify?version=2" }` matches nothing.
- **The default rule is last.** Move it to the top and the three rules below it become unreachable, with no error from any tool.

---

## Step 4: Check the Objects Against Each Other

```sh
istioctl analyze -n routing-demo
```

```text
✔ No validation issues found when analyzing namespace: routing-demo.
```

`istioctl analyze` checks the two objects against each other. It reports a `VirtualService` that names a subset the `DestinationRule` never defined (`IST0101`). Run it before you call any routing task finished.

---

## Step 5: Verify With Live Traffic

The grader sends real requests, so check the same way. Start with default traffic, and send enough requests that one lucky answer from v1 cannot fool you:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL"]
```

Twenty requests give one distinct answer. If you still see `["EMAIL","SMS"]`, the default rule does not route to `v1`, or there is no default rule and traffic is still load balanced across both versions.

Now each specific rule:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST -H "testing: true" http://notification-service/notify
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST http://notification-service/notify/beta
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST 'http://notification-service/notify?version=2'
```

```text
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
```

Any of these returning `["EMAIL"]` means the default rule is sitting above it.

Finally, send the near-miss that the grader also checks. A header that is present but has the wrong value must fall through to `v1`:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST -H "testing: yes" http://notification-service/notify
```

```text
["EMAIL"]
```

That proves the rule matches the value `true`, not only the presence of the header.

---

## Step 6: Confirm the Proxy Holds the Routes

Here the behaviour is already right, so the proxy must hold your configuration. On a task that does *not* work, this command tells you whether the configuration reached the proxy:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo | grep notification
```

```text
80     notification-service, notification-service.routing-demo + 1 more...     /notify/beta*
80     notification-service, notification-service.routing-demo + 1 more...     /*
```

If a `VirtualService` exists in `kubectl` but its host is missing here, the problem is between `istiod` (the control plane) and the sidecar proxy, not in your YAML.

---

## Common Mistakes

- **Default route first.** Every request matches it, the three rules below never run, and nothing reports an error.
- **Unquoted `true` or `2`.** Rejected as a boolean or an integer; quote header and query values.
- **`uri` used for the query string.** The `uri` match stops at the `?`.
- **Subset name typo.** `subset: v3` against a `DestinationRule` defining `v1`/`v2` gives a bare 503; `istioctl analyze` names it as `IST0101`.
- **Objects in the wrong namespace.** Istio fills in short host names from the object's own namespace, so a `VirtualService` in `default` never matches, and gives no error.
- **Changing the Service selector to split versions.** The grader rejects it. The Service must keep selecting on `app` alone.
