# Solution Walkthrough

The task has two halves that affect each other. Build the routing first and prove that it works. Then add the scoping, and watch how a `Sidecar` that leaves out its own namespace breaks the routing you just finished.

---

## Step 1: Read the Starting State

List the pods with their labels, the selector of the `catalog` Service, and the namespaces with sidecar injection switched on:

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

With no rules, requests reach both versions, and both outside Services answer:

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

A `DestinationRule` defines subsets: named groups of pods, selected by pod labels. Write it to a file and apply the file. A file is something you can read again, edit and apply again, which saves time in an exam.

Save this as `destinationrule-catalog.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f destinationrule-catalog.yaml
```

Then check the result:

```sh
istioctl proxy-config cluster deploy/shopper -n storefront | grep catalog
```

```text
catalog.storefront.svc.cluster.local   8000   -    outbound   EDS
catalog.storefront.svc.cluster.local   8000   v1   outbound   EDS
catalog.storefront.svc.cluster.local   8000   v2   outbound   EDS
```

The `shopper` proxy now has three clusters for `catalog` where it had one. A cluster is Envoy's name for a group of destination pods. Traffic does not change yet: subsets only define the groups, and no route uses them.

---

## Step 3: Route, Specific Rules First

A `VirtualService` holds the routing rules for a host. The proxy checks the rules from top to bottom and uses the first one that matches, so the three specific rules go first and the default rule goes last.

Save this as `virtualservice-catalog.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-catalog.yaml
```

Then check the result:

```sh
istioctl analyze -n storefront
```

```text
✔ No validation issues found when analyzing namespace: storefront.
```

Three details often fail this task: `exact: "mobile"` and `exact: "1"` are quoted, the query rule uses `queryParams` and not `uri`, and the default rule is **last**.

Now check all five cases that the grader checks:

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

The last line is the near-miss: a request that has the header with the wrong value must fall through to the default rule.

---

## Step 4: Scope the Namespace

A `Sidecar` resource limits which hosts the proxies in its namespace hold configuration for. Before you change anything, count the clusters in the `shopper` proxy:

```sh
istioctl proxy-config cluster deploy/shopper -n storefront | wc -l
```

```text
      36
```

Now write the `Sidecar`: three egress hosts, and no `workloadSelector`.

Save this as `sidecar-default.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f sidecar-default.yaml
```

Then check the result:

```sh
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

`archive` is gone. `catalog` and both of its subsets are still there, because `./*` means every host in the proxy's own namespace.

**This is the interaction the capstone tests.** Remove `./*` from that list and run the routing checks again: every request gets a `503`, because the proxy no longer has a `catalog` cluster to send it to. The `VirtualService` is still correct. The destination is missing from the proxy's configuration.

---

## Step 5: Verify Both Halves Together

Send requests to both outside Services, and repeat two routing checks:

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

`pricing` answers, `coldstore` does not (`000` means curl got no HTTP response), and the routing still works. Confirm that the `Sidecar` stopped the traffic, and that `coldstore` still runs:

```sh
kubectl -n archive get deploy,svc
```

```text
deployment.apps/coldstore   1/1   Running
service/coldstore           ClusterIP   8000/TCP
```

---

## Common Mistakes

- **`Sidecar` without `./*`.** This breaks the routing half completely: every `catalog` request gets a `503`, and the `VirtualService` is not at fault.
- **Leaving out `istio-system/*`.** Application traffic still works, so a quick test does not show the mistake. The grader checks for the entry.
- **Default route first.** The three match rules can never match, and nothing reports an error.
- **Using `uri` for the query parameter.** The `uri` match stops at the `?`.
- **Unquoted `exact: 1`.** YAML reads it as a number, and the API server rejects it. Quote query and header values.
- **Adding a `workloadSelector`.** The specification asks for a `Sidecar` for the whole namespace.
- **Deleting or scaling down `coldstore`.** The grader checks that it still runs.
- **Testing straight after you apply the `Sidecar`.** `istiod` needs a few seconds to push the change to the proxies. Wait before you decide that the object is wrong.
