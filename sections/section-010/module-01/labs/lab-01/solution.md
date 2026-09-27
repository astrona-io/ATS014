# Solution Walkthrough

Two objects, in this order: the `DestinationRule` first so the subset names exist, then the `VirtualService` that uses them. The last step is the one the grader cares most about — proving the rule order leaves every rule reachable.

---

## Step 1: Read the Starting State

Confirm what you have before changing anything. This is the habit the exam rewards.

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

Three facts to take from that: the pods carry a `version` label, the Service deliberately ignores it, and no Istio routing exists yet.

Now the baseline. Both versions answer, in no pattern:

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

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

```text
destinationrule.networking.istio.io/notification-service created
```

Check what it built, and confirm each subset actually selects a pod — a subset whose labels match nothing is legal configuration and a 503 later:

```sh
istioctl proxy-config cluster deploy/tester -n routing-demo | grep notification
```

```text
notification-service.routing-demo.svc.cluster.local   80   -    outbound   EDS
notification-service.routing-demo.svc.cluster.local   80   v1   outbound   EDS
notification-service.routing-demo.svc.cluster.local   80   v2   outbound   EDS
```

Re-run the baseline loop now and the split is unchanged. That is correct: subsets are vocabulary, not behaviour.

---

## Step 3: Write the VirtualService — Specific Rules First

The three match rules go above the default. Envoy evaluates top down and stops at the first match, so a rule with no `match` block can only ever be last.

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

```text
virtualservice.networking.istio.io/notification-service created
```

Three details that are each a failed task if you get them wrong:

- **`exact: "true"` is quoted.** Unquoted `true` is a YAML boolean and the apply is rejected. The same applies to `exact: "2"`.
- **The query rule uses `queryParams`, not `uri`.** The `uri` value stops at the `?`, so `uri: { exact: "/notify?version=2" }` matches nothing.
- **The default rule is last.** Move it to the top and the three rules above become unreachable, with no error from anywhere.

---

## Step 4: Check the Objects Against Each Other

```sh
istioctl analyze -n routing-demo
```

```text
✔ No validation issues found when analyzing namespace: routing-demo.
```

`analyze` cross-references the two objects — it is what catches a `VirtualService` naming a subset the `DestinationRule` never defined (`IST0101`). Run it before you believe any routing task is finished.

---

## Step 5: Verify With Live Traffic

The grader sends real requests, so verify the same way. Default traffic first, and use enough samples that "it went to v1 once" cannot fool you:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort -u
```

```text
["EMAIL"]
```

Twenty requests, one distinct answer. If you still see `["EMAIL","SMS"]` in there, the default rule is not routing to `v1` — or there is no default rule and traffic is still load balancing across both versions.

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

Finally the near-miss the grader also checks — a header that is present but has the wrong value must fall through:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST -H "testing: yes" http://notification-service/notify
```

```text
["EMAIL"]
```

That proves the rule matches the value `true` rather than merely the presence of the header.

---

## Step 6: Confirm the Proxy Holds the Routes

Behaviour being right and the proxy having your configuration are the same thing here, but on a task that is *not* working this is the command that tells you which half is broken:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo | grep notification
```

```text
80     notification-service, notification-service.routing-demo + 1 more...     /notify/beta*
80     notification-service, notification-service.routing-demo + 1 more...     /*
```

If a `VirtualService` exists in `kubectl` but its host is absent here, the problem is between the control plane and the sidecar — not in your YAML.

---

## Common Mistakes

- **Default route first.** Every request matches it, the three rules below never run, and nothing reports an error.
- **Unquoted `true` or `2`.** Rejected as a boolean or an integer; quote header and query values.
- **`uri` used for the query string.** The `uri` match stops at the `?`.
- **Subset name typo.** `subset: v3` against a `DestinationRule` defining `v1`/`v2` gives a bare 503; `istioctl analyze` names it as `IST0101`.
- **Objects in the wrong namespace.** Short host names resolve relative to the object's own namespace, so a `VirtualService` in `default` silently never fires.
- **Changing the Service selector to split versions.** That defeats the exercise and the grader rejects it — the Service must keep selecting on `app` alone.
