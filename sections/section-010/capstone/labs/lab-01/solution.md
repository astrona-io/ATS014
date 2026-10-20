# Solution Walkthrough

The task has two halves that affect each other: routing (items 1 to 5) and scoping (items 6 to 9). Item 10 proves that the two halves work together, and item 11 proves that you left everything else alone. Build the routing first and prove it. Then add the scoping.

---

## Start: Read The Starting State

The task describes three namespaces with sidecar injection, and no Istio traffic configuration. Check the pods, the selector of the `catalog` Service, and the namespaces:

```sh
kubectl -n storefront get pods -L app,version
kubectl -n storefront get svc catalog -o jsonpath='{.spec.selector}{"\n"}'
kubectl get ns -l istio-injection=enabled
kubectl get sidecar,virtualservice,destinationrule -A
```

```text
NAME                          READY   STATUS    RESTARTS   AGE   APP       VERSION
catalog-v1-7944b7dd96-9pgqk   2/2     Running   0          6s    catalog   v1
catalog-v2-7d967b7d8b-6s56z   2/2     Running   0          6s    catalog   v2
shopper-787977f855-ngdj5      2/2     Running   0          6s    shopper   
{"app":"catalog"}
NAME         STATUS   AGE
archive      Active   6s
partners     Active   6s
storefront   Active   6s
No resources found
```

The pods carry a `version` label, and the Service selects on `app` only. Without any rule, requests reach both versions, and both outside Services answer. Prove it with 20 requests and two calls from `shopper`:

```sh
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort | uniq -c
for url in http://pricing.partners:8000/get http://coldstore.archive:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
```

```text
   7 ["EMAIL","SMS"]
  13 ["EMAIL"]
http://pricing.partners:8000/get -> 200
http://coldstore.archive:8000/get -> 200
```

Save the identity of the Deployments. Item 11 compares against it:

```sh
for ns in storefront partners archive; do
  kubectl -n $ns get deploy -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid | grep -v NS
done
```

```text
storefront   catalog-v1   1      c2d93c97-2c0c-4a94-a025-ca47fe36b4f0
storefront   catalog-v2   1      3592cf5f-90cf-42ca-9bd7-46dd36dd7f78
storefront   shopper      1      7066d26a-b3aa-4ad0-abab-8901998637ce
partners   pricing   1      bf7a8437-beda-4e8c-8d69-7254b966839d
archive   coldstore   1      f1ae1955-239d-430d-b9cd-45f508043635
```

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `catalog` in `storefront` that defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label. A subset is a named group of pods.

A `DestinationRule` holds the policies for traffic to one host, and it defines the subsets. Create it first, because the `VirtualService` names the subsets. Save this as `destinationrule-catalog.yaml`:

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

```text
destinationrule.networking.istio.io/catalog created
```

Check item 1. Print the subsets, and list the clusters that the proxy of `shopper` holds for `catalog`. The proxy is the Envoy container that Istio adds to each pod, and a cluster is a named group of destination pods in Envoy:

```sh
kubectl -n storefront get destinationrule catalog -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
istioctl proxy-config cluster deploy/shopper -n storefront | grep catalog
```

```text
v1=v1
v2=v2
catalog.storefront.svc.cluster.local                           8000      -          outbound      EDS              catalog.storefront
catalog.storefront.svc.cluster.local                           8000      v1         outbound      EDS              catalog.storefront
catalog.storefront.svc.cluster.local                           8000      v2         outbound      EDS              catalog.storefront
```

There are exactly two subsets, and the proxy now has three clusters for `catalog` where it had one. Traffic does not change yet, because no route uses the subsets.

---

## Item 2: Route Three Kinds Of Request To `v2`

> **Task item 2:** A `VirtualService` named `catalog` in `storefront` for the host `catalog`, which sends these requests to subset **`v2`**:
>
> * requests with the header **`x-channel: mobile`**
> * requests whose URI path starts with **`/notify/preview`**
> * requests with the query parameter **`beta=1`**

A `VirtualService` holds the routing rules for a host. The proxy reads the rules from top to bottom and uses the first rule that matches. So the three specific rules go first, and the default rule goes last. Save this as `virtualservice-catalog.yaml`:

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

```text
virtualservice.networking.istio.io/catalog created
```

Three details fail this task if you get them wrong. Quote `"mobile"` and `"1"`, because YAML reads an unquoted `1` as a number and the API server rejects it. Use `queryParams` for the query parameter, because a `uri` match stops at the `?`. Put the default rule last.

Check item 2. Let Istio check the objects, then send one request of each kind:

```sh
istioctl analyze -n storefront
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: mobile" http://catalog:8000/notify
echo
kubectl -n storefront exec deploy/shopper -- curl -s -X POST http://catalog:8000/notify/preview
echo
kubectl -n storefront exec deploy/shopper -- curl -s -X POST 'http://catalog:8000/notify?beta=1'
echo
```

```text

✔ No validation issues found when analyzing namespace: storefront.
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
```

All three requests reached `v2`, which answers `["EMAIL","SMS"]`. If one of them answers `["EMAIL"]`, wait a few seconds for `istiod`, the Istio control plane, to send the rules to the proxy, and run it again.

---

## Item 3: Every Other Request Reaches `v1`

> **Task item 3:** Every other request must reach subset **`v1`**, every time, not only sometimes.

Send 20 plain requests, so that one lucky answer cannot fool you:

```sh
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort | uniq -c
```

```text
  20 ["EMAIL"]
```

All 20 requests reached `v1`. At the start, the same loop gave a mix of both versions.

---

## Item 4: All Three Specific Rules Are Reachable

> **Task item 4:** All three specific rules must be reachable. A default route placed above them gives no error, but it still fails the task.

Item 2 already proved that each specific request reaches `v2`, which the default rule would never do. Now check the order of the rules in the object:

```sh
kubectl -n storefront get virtualservice catalog \
  -o jsonpath='{range .spec.http[*]}{.route[0].destination.subset}{" <- "}{.match}{"\n"}{end}'
```

```text
v2 <- [{"headers":{"x-channel":{"exact":"mobile"}}}]
v2 <- [{"uri":{"prefix":"/notify/preview"}}]
v2 <- [{"queryParams":{"beta":{"exact":"1"}}}]
v1 <- 
```

The three rules with a `match` come first. The rule without a `match` is last.

---

## Item 5: The Header Rule Matches The Value `mobile`

> **Task item 5:** A request with the header `x-channel: web` must reach `v1`. The header rule matches the value `mobile`, not only the presence of the header.

```sh
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: web" http://catalog:8000/notify
echo
```

```text
["EMAIL"]
```

The header is present, but its value is `web`, so the request falls through to the default rule and reaches `v1`.

---

## Items 6 And 7: Write The `Sidecar`

> **Task item 6:** A `Sidecar` named **`default`** in `storefront` that applies to **every workload in that namespace**, so it has no `workloadSelector`. It is the only `Sidecar` in `storefront`.
>
> **Task item 7:** Its `egress` hosts must be exactly three entries: the proxy's **own namespace**, **`istio-system`**, and **`partners`**.

A `Sidecar` resource limits which hosts the proxies of a namespace know about. Count the clusters of the `shopper` proxy before you change anything:

```sh
istioctl proxy-config cluster deploy/shopper -n storefront | wc -l
```

```text
      31
```

Both items describe one object, so you write it once. Save this as `sidecar-default.yaml`:

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

```text
sidecar.networking.istio.io/default created
```

Check items 6 and 7. List the `Sidecar` objects, print the selector, and print the host list:

```sh
kubectl -n storefront get sidecar
kubectl -n storefront get sidecar default -o jsonpath='workloadSelector=[{.spec.workloadSelector}]{"\n"}'
kubectl -n storefront get sidecar default -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
```

```text
NAME      AGE
default   17s
workloadSelector=[]
["./*","istio-system/*","partners/*"]
```

There is exactly one `Sidecar`, it has no selector, and it lists exactly three hosts.

---

## Item 8: `pricing` Still Answers

> **Task item 8:** A request from `shopper` to `http://pricing.partners:8000/get` must still return **200**.

```sh
kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://pricing.partners:8000/get
```

```text
200
```

The request returns `200`, because `partners/*` is in the host list.

---

## Item 9: `archive` Is Gone From The Proxy

> **Task item 9:** `archive` must be absent from the `shopper` proxy's cluster list, and a request to `http://coldstore.archive:8000/get` must **not** return 200.

```sh
istioctl proxy-config cluster deploy/shopper -n storefront | wc -l
istioctl proxy-config cluster deploy/shopper -n storefront | grep -E 'catalog|pricing|coldstore|archive'
kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://coldstore.archive:8000/get
```

```text
      27
catalog.storefront.svc.cluster.local                           8000      -          outbound      EDS              catalog.storefront
catalog.storefront.svc.cluster.local                           8000      v1         outbound      EDS              catalog.storefront
catalog.storefront.svc.cluster.local                           8000      v2         outbound      EDS              catalog.storefront
pricing.partners.svc.cluster.local                             8000      -          outbound      EDS              
502
```

The cluster list went from 31 lines to 27. There is no line for `coldstore` or `archive`, and the request fails with `502`. The task says that the mesh runs with `outboundTrafficPolicy: REGISTRY_ONLY`. A host that is not in the configuration of the proxy therefore fails, and the request does not leave through a passthrough. If the list still shows `coldstore`, wait a few seconds and run the commands again.

---

## Item 10: The Routing Still Works With The `Sidecar`

> **Task item 10:** The routing from the first half must still work with the `Sidecar` in place. If the proxy's own namespace is not in the egress hosts, the proxy loses the `catalog` clusters and the routing breaks.

Repeat the routing checks of items 3 and 5, and one request of each specific kind:

```sh
kubectl -n storefront exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://catalog:8000/notify; echo; done' | sort | uniq -c
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: mobile" http://catalog:8000/notify
echo
kubectl -n storefront exec deploy/shopper -- curl -s -X POST http://catalog:8000/notify/preview
echo
kubectl -n storefront exec deploy/shopper -- curl -s -X POST 'http://catalog:8000/notify?beta=1'
echo
kubectl -n storefront exec deploy/shopper -- curl -s -X POST -H "x-channel: web" http://catalog:8000/notify
echo
```

```text
  20 ["EMAIL"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL","SMS"]
["EMAIL"]
```

The routing is unchanged, because `./*` keeps the `catalog` clusters in the proxy. This is the interaction that this capstone tests. To see the failure, save a copy of the file without the `./*` line as `sidecar-no-own-namespace.yaml`. Apply it, and run one routing request:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: storefront
spec:
  egress:
    - hosts:
        - "istio-system/*"
        - "partners/*"
```

```sh
kubectl apply -f sidecar-no-own-namespace.yaml
sleep 8
kubectl -n storefront exec deploy/shopper -- curl -s -o /dev/null -w '%{http_code}\n' -X POST http://catalog:8000/notify
istioctl proxy-config cluster deploy/shopper -n storefront | grep -c catalog
```

```text
sidecar.networking.istio.io/default configured
502
0
```

The request fails, and the proxy holds no `catalog` cluster. The `VirtualService` is still correct, and the destination is missing from the configuration of the proxy. Restore the correct `Sidecar` and check again:

```sh
kubectl apply -f sidecar-default.yaml
```

---

## Item 11: Nothing Else Changed

> **Task item 11:** Do not change the `catalog` Service selector, do not add or remove Deployments, and do not delete or scale down `coldstore`. The `Sidecar` must stop the traffic to `archive`, not the removal of the target.

Run the identity commands from the Start section again:

```sh
kubectl -n storefront get svc catalog -o jsonpath='{.spec.selector}{"\n"}'
for ns in storefront partners archive; do
  kubectl -n $ns get deploy -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid | grep -v NS
done
```

```text
{"app":"catalog"}
storefront   catalog-v1   1      c2d93c97-2c0c-4a94-a025-ca47fe36b4f0
storefront   catalog-v2   1      3592cf5f-90cf-42ca-9bd7-46dd36dd7f78
storefront   shopper      1      7066d26a-b3aa-4ad0-abab-8901998637ce
partners   pricing   1      bf7a8437-beda-4e8c-8d69-7254b966839d
archive   coldstore   1      f1ae1955-239d-430d-b9cd-45f508043635
```

The Service still selects on `app` only, and all Deployments have the same `UID` values. `coldstore` still runs with one replica. The `Sidecar` stopped the traffic, and nothing was deleted.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/capstone/labs/lab-01
```

The grader checks both halves with live requests and with the configuration of the `shopper` proxy.

---

## Mistakes That Fail The Grader

- **A `Sidecar` without `./*` (items 7 and 10).** This breaks the routing half completely. Every `catalog` request fails, and the `VirtualService` is not at fault.
- **Leaving out `istio-system/*` (item 7).** Application traffic still works, so a quick test does not show the mistake. The grader checks for the entry.
- **The default route first (items 3 and 4).** The three match rules can never match, and nothing reports an error.
- **Using `uri` for the query parameter (item 2).** The `uri` match stops at the `?`.
- **Unquoted `exact: 1` (item 2).** YAML reads it as a number, and the API server rejects it. Quote query and header values.
- **Adding a `workloadSelector` (item 6).** The task asks for a `Sidecar` for the whole namespace.
- **Deleting or scaling down `coldstore` (item 11).** The grader checks that it still runs.
- **Testing straight after you apply the `Sidecar` (items 8 to 10).** `istiod` needs a few seconds to send the change to the proxies. Wait before you decide that the object is wrong.
