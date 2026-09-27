# Solution Walkthrough

Two halves that interact. Build the routing first and prove it works, then add the scoping — and watch that a `Sidecar` which forgets its own namespace destroys the routing you just finished.

---

## Step 1: Read the Starting State

```sh
kubectl -n storefront get pods --show-labels
kubectl -n storefront get svc catalog -o jsonpath='{.spec.selector}{"\n"}'
kubectl get ns -l istio-injection=enabled
```

```text
catalog-v1-6c7f9d4b8b-4nplq   2/2   Running   app=catalog,version=v1,...
catalog-v2-79b5c86dd7-tq8xw   2/2   Running   app=catalog,version=v2,...
shopper-5d9f7c6b4c-w2klm      2/2   Running   app=shopper,...
{"app":"catalog"}
NAME         STATUS
archive      Active
partners     Active
storefront   Active
```

Baseline traffic hits both versions, and all three namespaces are reachable:

```sh
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort | uniq -c
for url in http://pricing.partners:8000/get http://coldstore.archive:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
```

```text
  12 ["EMAIL"]
   8 ["EMAIL","SMS"]
http://pricing.partners:8000/get -> 200
http://coldstore.archive:8000/get -> 200
```

---

## Step 2: Define the Subsets

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: catalog
  namespace: storefront
spec:
  host: catalog
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
EOF
istioctl proxy-config cluster deploy/shopper -n storefront | grep catalog
```

```text
catalog.storefront.svc.cluster.local   8000   -    outbound   EDS
catalog.storefront.svc.cluster.local   8000   v1   outbound   EDS
catalog.storefront.svc.cluster.local   8000   v2   outbound   EDS
```

Three clusters where there was one. Traffic is unchanged — subsets are vocabulary.

---

## Step 3: Route, Specific Rules First

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: catalog
  namespace: storefront
spec:
  hosts:
    - catalog
  http:
    - match:
        - headers:
            x-channel:
              exact: "mobile"
      route:
        - destination: { host: catalog, subset: v2 }
    - match:
        - uri:
            prefix: /notify/preview
      route:
        - destination: { host: catalog, subset: v2 }
    - match:
        - queryParams:
            beta:
              exact: "1"
      route:
        - destination: { host: catalog, subset: v2 }
    - route:
        - destination: { host: catalog, subset: v1 }
EOF
istioctl analyze -n storefront
```

```text
✔ No validation issues found when analyzing namespace: storefront.
```

The three details that fail a task: `exact: "mobile"` and `exact: "1"` are quoted, the query rule uses `queryParams` rather than `uri`, and the default rule is **last**.

Verify all five cases the grader checks:

```sh
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort -u
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: mobile" http://catalog:8000/notify
kubectl -n storefront exec deploy/shopper -- curl -s -X POST http://catalog:8000/notify/preview
kubectl -n storefront exec deploy/shopper -- curl -s -X POST 'http://catalog:8000/notify?beta=1'
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: web" http://catalog:8000/notify
```

```text
["EMAIL"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL"]
```

The last line is the near-miss: a present header with the wrong value must fall through.

---

## Step 4: Scope the Namespace

Measure before you change anything:

```sh
istioctl proxy-config cluster deploy/shopper -n storefront | wc -l
```

```text
      36
```

Now the `Sidecar`. Three entries, no selector:

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: storefront
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
        - "partners/*"
EOF
sleep 3
istioctl proxy-config cluster deploy/shopper -n storefront | wc -l
istioctl proxy-config cluster deploy/shopper -n storefront | grep -E 'catalog|partners|archive'
```

```text
      18
catalog.storefront.svc.cluster.local   8000   -    outbound   EDS
catalog.storefront.svc.cluster.local   8000   v1   outbound   EDS
catalog.storefront.svc.cluster.local   8000   v2   outbound   EDS
pricing.partners.svc.cluster.local     8000   -    outbound   EDS
```

`archive` is gone. `catalog` — including both subsets — survived, because `./*` covers the proxy's own namespace.

**This is the interaction the capstone is testing.** Drop `./*` from that list and re-run the routing checks: every request 503s, because the proxy no longer has a `catalog` cluster to route to. The `VirtualService` is still perfect; the proxy was simply never told the destination exists.

---

## Step 5: Verify Both Halves Together

```sh
for url in http://pricing.partners:8000/get http://coldstore.archive:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort -u
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: mobile" http://catalog:8000/notify
```

```text
http://pricing.partners:8000/get -> 200
http://coldstore.archive:8000/get -> 000
["EMAIL"]
["EMAIL","SMS"]
```

Partners reachable, archive not, routing still correct. Confirm you stopped the traffic by scoping rather than by deleting:

```sh
kubectl -n archive get deploy,svc
```

```text
deployment.apps/coldstore   1/1   Running
service/coldstore           ClusterIP   8000/TCP
```

---

## Common Mistakes

- **`Sidecar` without `./*`.** Breaks the routing half completely — 503 on every `catalog` request, with a `VirtualService` that is not at fault.
- **Omitting `istio-system/*`.** Application traffic still works, so the mistake survives a casual test; telemetry and control-plane paths do not.
- **Default route first.** The three match rules become unreachable, silently.
- **`uri` used for the query parameter.** The `uri` match stops at the `?`.
- **Unquoted `exact: 1`.** Parsed as an integer and rejected — quote query and header values.
- **Adding a `workloadSelector`.** The specification says namespace-wide.
- **Deleting or scaling `coldstore`.** The grader checks it is still running.
- **Testing immediately after the `Sidecar` apply.** Wait a few seconds for the push before deciding the object is wrong.
