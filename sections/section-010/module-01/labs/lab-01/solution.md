# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. You build two objects. Item 1 creates the `DestinationRule`. Items 2, 3 and 4 add one rule each to the `VirtualService`. Items 5 to 7 prove the result.

---

## Start: Read The Starting State

The task describes two versions of one application behind one Service, and no Istio routing. Check that this is true:

```sh
kubectl -n routing-demo get pods -L app,version
kubectl -n routing-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n routing-demo get destinationrule,virtualservice
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE   APP                    VERSION
notification-service-v1-54dd46d4b6-jz6fl   2/2     Running   0          58s   notification-service   v1
notification-service-v2-d79d6dcc4-z9cnc    2/2     Running   0          58s   notification-service   v2
tester-69699fd775-4tdl9                    2/2     Running   0          58s   tester                 
{"app":"notification-service"}
No resources found in routing-demo namespace.
```

The pods carry a `version` label. The Service selects on `app` only, so it sends requests to both versions. Prove it with 20 requests from the `tester` pod:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
   8 ["EMAIL","SMS"]
  12 ["EMAIL"]
```

Both versions answer. Before you change anything, save the identity of the Deployments. Item 7 compares against it:

```sh
kubectl -n routing-demo get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
```

```text
NAME                      REPL   UID
notification-service-v1   1      13c1d98c-69c1-4d8d-a511-cdd70d7f0d37
notification-service-v2   1      3a33f1a0-8b37-459e-afe1-dadb0b4f5d23
tester                    1      4a4511a2-d158-4ed7-9573-cf039be29ec8
```

---

## Item 1: Define The Subsets `v1` And `v2`

> **Task item 1:** A `DestinationRule` named `notification-service` defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. It also defines subsets, which are named groups of pods picked by labels. Create it first, because the `VirtualService` names these subsets.

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

Check item 1. Print the subsets, then look at the clusters that `istiod`, the Istio control plane, built in the proxy of the `tester` pod. A cluster is a named destination in Envoy:

```sh
kubectl -n routing-demo get destinationrule notification-service \
  -o jsonpath='{range .spec.subsets[*]}{.name}{" "}{.labels}{"\n"}{end}'
istioctl proxy-config cluster deploy/tester -n routing-demo | grep -E "notification|SERVICE"
```

```text
v1 {"version":"v1"}
v2 {"version":"v2"}
SERVICE FQDN                                                   PORT      SUBSET     DIRECTION     TYPE             DESTINATION RULE
notification-service.routing-demo.svc.cluster.local            80        -          outbound      EDS              notification-service.routing-demo
notification-service.routing-demo.svc.cluster.local            80        v1         outbound      EDS              notification-service.routing-demo
notification-service.routing-demo.svc.cluster.local            80        v2         outbound      EDS              notification-service.routing-demo
```

There are exactly two subsets, and the proxy holds a cluster for each. The 20-request loop from the Start section still gives a mixed answer. That is correct: a `DestinationRule` only names the subsets. It does not route any request.

---

## Item 2: Route The Header `testing: true` To `v2`

> **Task item 2:** A `VirtualService` named `notification-service` routes requests carrying the header **`testing: true`** to subset **`v2`**.

A `VirtualService` sets where requests to a host go. It holds a list of rules. The proxy reads the rules from top to bottom and uses the first rule that matches. A rule without a `match` block matches every request, so it must be last.

Start with the header rule and the default rule. Save this as `virtualservice-notification-service.yaml`:

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

Quote `"true"`. Without the quotes, YAML reads `true` as a boolean and the apply fails.

Check item 2. Send one request with the header, and one with a wrong value:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST -H "testing: true" http://notification-service/notify
echo
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST -H "testing: yes" http://notification-service/notify
echo
```

```text
["EMAIL","SMS"]
["EMAIL"]
```

The header `testing: true` reaches `v2`. The header `testing: yes` does not match, so it falls through to `v1`. This proves that the rule matches the value `true`, not only the presence of the header. If the first request returns `["EMAIL"]`, wait a few seconds for `istiod` to send the rule to the proxy, and run it again.

---

## Item 3: Route The Path `/notify/beta` To `v2`

> **Task item 3:** The same `VirtualService` routes requests whose URI starts with **`/notify/beta`** to subset **`v2`**.

Add a second specific rule. Put it above the default rule and below the header rule. Edit `virtualservice-notification-service.yaml` so that the `http` list looks like this:

```yaml
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
    - route:
        - destination:
            host: notification-service
            subset: v1
```

Apply the file again:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

```text
virtualservice.networking.istio.io/notification-service configured
```

Check item 3. Send a request to the beta path:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST http://notification-service/notify/beta
echo
```

```text
["EMAIL","SMS"]
```

The path reaches `v2`.

---

## Item 4: Route The Query Parameter `version=2` To `v2`

> **Task item 4:** The same `VirtualService` routes requests carrying the query parameter **`version=2`** to subset **`v2`**.

Add the third specific rule, again above the default rule. Use `queryParams`, not `uri`. The `uri` match stops at the `?`, so a `uri` rule never sees the query string. Quote `"2"` for the same reason as `"true"`. The full file now looks like this:

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
virtualservice.networking.istio.io/notification-service configured
```

Check item 4. Send one request with `version=2`, and one with `version=3`:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST 'http://notification-service/notify?version=2'
echo
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -X POST 'http://notification-service/notify?version=3'
echo
```

```text
["EMAIL","SMS"]
["EMAIL"]
```

The value `2` reaches `v2`, and the value `3` falls through to `v1`. Then let Istio check the two objects against each other:

```sh
istioctl analyze -n routing-demo
```

```text
✔ No validation issues found when analyzing namespace: routing-demo.
```

`istioctl analyze` reports a `VirtualService` that names a subset the `DestinationRule` never defined (message `IST0101`).

---

## Item 5: Every Other Request Goes To `v1`

> **Task item 5:** **Every other request** goes to subset **`v1`**. A request with no header, no matching path and no query parameter must reach `v1` every time, not only sometimes.

The last rule in the file is the default rule. Check it with enough requests that one lucky answer cannot fool you. Send 20 plain requests:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  20 ["EMAIL"]
```

All 20 requests reached `v1`. In the Start section the same loop gave a mix of both versions.

---

## Item 6: Every Specific Rule Is Reachable

> **Task item 6:** The three specific rules must each be reachable. A default route that swallows traffic before them is a failure, even though it produces no error.

You already proved that each rule is reachable. In items 2, 3 and 4, each specific request reached `v2`, which the default rule would never do. Now check the order in the file and in the proxy:

```sh
kubectl -n routing-demo get virtualservice notification-service \
  -o jsonpath='{range .spec.http[*]}{.route[0].destination.subset}{" <- "}{.match}{"\n"}{end}'
istioctl proxy-config routes deploy/tester -n routing-demo --name 80 | grep -E 'NAME|notification'
```

```text
v2 <- [{"headers":{"testing":{"exact":"true"}}}]
v2 <- [{"uri":{"prefix":"/notify/beta"}}]
v2 <- [{"queryParams":{"version":{"exact":"2"}}}]
v1 <- 
NAME     VHOST NAME                                                 DOMAINS                                                                                                 MATCH             VIRTUAL SERVICE
80       notification-service.routing-demo.svc.cluster.local:80     notification-service.routing-demo.svc.cluster.local., notification-service + 2 more...                  /*                notification-service.routing-demo
80       notification-service.routing-demo.svc.cluster.local:80     notification-service.routing-demo.svc.cluster.local., notification-service + 2 more...                  /notify/beta*     notification-service.routing-demo
80       notification-service.routing-demo.svc.cluster.local:80     notification-service.routing-demo.svc.cluster.local., notification-service + 2 more...                  /*                notification-service.routing-demo
80       notification-service.routing-demo.svc.cluster.local:80     notification-service.routing-demo.svc.cluster.local., notification-service + 2 more...                  /*                notification-service.routing-demo
```

The three specific rules come first, and the rule without a `match` is last. The proxy holds four routes in the same order. The `MATCH` column of this command shows only the path, so the header and query rules both appear as `/*`. If a rule with no `match` stood at the top, the three rules below it would never run, and no tool would report an error.

---

## Item 7: Nothing Else Changed

> **Task item 7:** Leave the Deployments and the Service unchanged. Do not add a third Deployment, and do not change the Service selector.

```sh
kubectl -n routing-demo get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
kubectl -n routing-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME                      REPL   UID
notification-service-v1   1      13c1d98c-69c1-4d8d-a511-cdd70d7f0d37
notification-service-v2   1      3a33f1a0-8b37-459e-afe1-dadb0b4f5d23
tester                    1      4a4511a2-d158-4ed7-9573-cf039be29ec8
{"app":"notification-service"}
```

The same three Deployments exist with the same `UID` values, and the Service still selects on `app` only.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-01
```

The grader sends real requests from the `tester` pod and reads the responses.

---

## Mistakes That Fail The Grader

- **Default route first (items 5 and 6).** Every request matches it, the rules below it never run, and nothing reports an error.
- **Unquoted `true` or `2` (items 2 and 4).** YAML reads them as a boolean and an integer, and the apply fails. Quote header and query values.
- **`uri` used for the query string (item 4).** The `uri` match stops at the `?`. Use `queryParams`.
- **A subset name typo (items 1 to 4).** `subset: v3` against a `DestinationRule` that defines `v1` and `v2` gives a `503`. `istioctl analyze` reports it as `IST0101`.
- **Objects in the wrong namespace.** Istio fills in short host names from the namespace of the object, so a `VirtualService` in `default` never matches and gives no error.
- **Changing the Service selector to split the versions (item 7).** The Service must keep selecting on `app` alone.
