# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. Item 1 creates the `DestinationRule`. Items 2 to 6 grow one `VirtualService` file, one feature at a time, and you apply the file after each item. Items 7 and 8 prove the rest.

---

## Start: Read The Starting State

The task says that two versions of the application run behind one Service and that no Istio routing exists. Check that this is true:

```sh
kubectl -n routing-demo get pods -L app,version
kubectl -n routing-demo get destinationrule,virtualservice
kubectl -n routing-demo get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE   APP                    VERSION
notification-service-v1-54dd46d4b6-dmvbs   2/2     Running   0          19s   notification-service   v1
notification-service-v2-d79d6dcc4-8jxjv    2/2     Running   0          19s   notification-service   v2
tester-69699fd775-r9kgm                    2/2     Running   0          19s   tester                 
No resources found in routing-demo namespace.
NAME                      REPL   UID
notification-service-v1   1      2203d054-08c7-46da-8fbf-328dfc759173
notification-service-v2   1      a76c7cae-8ab7-4c47-9d16-f4db2409405a
tester                    1      d70eb0c5-9ce3-4cbf-9864-9f5f06a1adb7
```

Nothing is configured. The application serves everything at `/notify` and knows nothing about `/legacy` or `/beta`. The `UID` values are the identity of the Deployments. Item 8 compares against them.

---

## Item 1: Define The Subsets `v1` And `v2`

> **Task item 1:** A `DestinationRule` named `notification-service` defines exactly two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. It also defines subsets, which are named groups of pods picked by labels. Item 3 routes to `v2`, so the subset names must exist first.

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

Check item 1:

```sh
kubectl -n routing-demo get destinationrule notification-service \
  -o jsonpath='{range .spec.subsets[*]}{.name}{" "}{.labels}{"\n"}{end}'
```

```text
v1 {"version":"v1"}
v2 {"version":"v2"}
```

There are exactly two subsets, and each selects on the `version` label. A `DestinationRule` routes no traffic by itself.

---

## Item 2: Redirect `/legacy` With A 301

> **Task item 2:** A `VirtualService` named `notification-service` answers any request whose URI starts with **`/legacy`** with a **301 redirect to `/notify`**. Nothing may be forwarded to a pod for these requests.

A `VirtualService` sets where requests to a host go. It holds a list of rules. The proxy reads the rules from top to bottom and uses the first rule that matches. A proxy is the Envoy container that Istio adds to each pod. The proxy of the client answers a `redirect` rule itself and forwards nothing.

A rule with `redirect` cannot also have a `route`. They are alternatives. Put the redirect rule first, because the rules below it are broader. Start the file with the redirect rule and the default rule for item 7.

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
        - uri:
            prefix: /legacy
      redirect:
        uri: /notify
        redirectCode: 301
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

Check item 2. Send a request to a path below `/legacy`, and print the response headers:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'legacy: %{http_code} -> %{redirect_url}\n' http://notification-service/legacy/anything
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null http://notification-service/legacy/anything
```

```text
legacy: 301 -> http://notification-service/notify
HTTP/1.1 301 Moved Permanently
location: http://notification-service/notify
date: Tue, 20 Oct 2026 20:06:39 GMT
server: envoy
content-length: 0

```

The status is `301`, and the `location` header points to `/notify`. The header `server: envoy` shows that the proxy answered. No pod was involved. If you get another status, wait a few seconds for `istiod`, the Istio control plane, to send the rule to the proxy, and run the command again.

---

## Item 3: Rewrite `/beta` And Route It To `v2`

> **Task item 3:** Requests whose URI starts with **`/beta`** are **rewritten** so the matched prefix becomes **`/`** (`/beta/notify` must reach the application as `/notify`), and are routed to subset **`v2`**.

Add this rule to `virtualservice-notification-service.yaml`, between the redirect rule and the default rule:

```yaml
    - match:
        - uri:
            prefix: /beta
      rewrite:
        uri: /
      route:
        - destination:
            host: notification-service
            subset: v2
```

`rewrite.uri` replaces only the matched prefix. So `/beta/notify` becomes `/notify`, and the application receives a path it knows. Apply the file again:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

```text
virtualservice.networking.istio.io/notification-service configured
```

Check item 3 in two ways. First, send a request. The application answers with the `v2` response only if it received `/notify`:

```sh
kubectl -n routing-demo exec deploy/tester -- curl -s http://notification-service/beta/notify
echo
```

```text
["EMAIL","SMS"]
```

Second, read the rewrite from the route table of the proxy. No access log shows a rewrite, because Istio logs the original path. The compiled route is the evidence:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo -o json | grep -E '"/beta"|prefixRewrite'
```

```text
                            "prefix": "/beta",
                            "prefixRewrite": "/",
```

The matched prefix and its replacement sit on the same route entry.

---

## Item 4: Add The Response Header `x-served-by`

> **Task item 4:** Every response leaving this service carries the response header **`x-served-by: notification`**.

`headers` belongs to one rule, not to the whole object. The redirect rule forwards nothing and needs no header. Both rules that route requests need it. Add this block to the `/beta` rule and to the default rule. Place it before `route:` in each rule:

```yaml
      headers:
        response:
          set:
            x-served-by: notification
```

Apply the file again:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

```text
virtualservice.networking.istio.io/notification-service configured
```

Check item 4. Request one path of each serving rule, and print the header:

```sh
kubectl -n routing-demo exec deploy/tester -- curl -s -D - -o /dev/null http://notification-service/notify | grep -i x-served-by
kubectl -n routing-demo exec deploy/tester -- curl -s -D - -o /dev/null http://notification-service/beta/notify | grep -i x-served-by
```

```text
x-served-by: notification
x-served-by: notification
```

Both rules add the header.

---

## Item 5: Remove The Request Header `x-internal-token`

> **Task item 5:** The request header **`x-internal-token`** is **removed** before any request is forwarded upstream.

Extend the `headers` block of both serving rules. `remove` is a list of header names, not a map:

```yaml
      headers:
        request:
          remove:
            - x-internal-token
        response:
          set:
            x-served-by: notification
```

Apply the file again:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

```text
virtualservice.networking.istio.io/notification-service configured
```

Check item 5. The application does not print its request headers, so read the compiled routes of the proxy:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo -o json | grep -B1 -A2 requestHeadersToRemove
```

```text
                        },
                        "requestHeadersToRemove": [
                            "x-internal-token"
                        ],
--
                        },
                        "requestHeadersToRemove": [
                            "x-internal-token"
                        ],
```

Two routes remove the header, one for each serving rule.

---

## Item 6: Allow Cross-Origin Requests From One Origin

> **Task item 6:** Cross-origin requests from exactly **`https://shop.example.com`** are permitted, for methods **`GET`** and **`POST`**.

CORS (cross-origin resource sharing) lets a browser page from one origin call a service on another origin. The service allows it with `access-control-*` response headers. Add `corsPolicy` to both serving rules, next to `headers`. The field `allowOrigins` takes string matches, so write `exact:` and the URL.

The full file now looks like this:

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
        - uri:
            prefix: /legacy
      redirect:
        uri: /notify
        redirectCode: 301
    - match:
        - uri:
            prefix: /beta
      rewrite:
        uri: /
      headers:
        request:
          remove:
            - x-internal-token
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods:
          - GET
          - POST
      route:
        - destination:
            host: notification-service
            subset: v2
    - headers:
        request:
          remove:
            - x-internal-token
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods:
          - GET
          - POST
      route:
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

Check item 6. Send a request with the allowed origin, and count the header for another origin:

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null -H "Origin: https://shop.example.com" -X POST http://notification-service/notify | grep -i access-control-allow-origin
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null -H "Origin: https://evil.example.com" -X POST http://notification-service/notify | grep -ci access-control-allow-origin
```

```text
access-control-allow-origin: https://shop.example.com
0
```

The allowed origin gets the `access-control-allow-origin` header. The other origin gets none (`0` lines).

---

## Item 7: Every Other Request Goes To `v1`

> **Task item 7:** **Every other request** goes to subset **`v1`**.

The last rule in the file is the default rule. Send 20 plain requests, and one request to the beta path for comparison:

```sh
kubectl -n routing-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
kubectl -n routing-demo exec deploy/tester -- curl -s -X POST http://notification-service/beta/notify
echo
```

```text
  20 ["EMAIL"]
["EMAIL","SMS"]
```

All 20 plain requests reached `v1`, and the beta path reached `v2`. This also shows that the rule order is right. A default rule above the others would send everything to `v1`.

---

## Item 8: Nothing Else Changed

> **Task item 8:** Leave the Deployments and the Service unchanged. Do not add a third Deployment, and do not change the Service selector.

Compare with the Start section, and let Istio check the two objects against each other:

```sh
kubectl -n routing-demo get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
kubectl -n routing-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
istioctl analyze -n routing-demo
```

```text
NAME                      REPL   UID
notification-service-v1   1      2203d054-08c7-46da-8fbf-328dfc759173
notification-service-v2   1      a76c7cae-8ab7-4c47-9d16-f4db2409405a
tester                    1      d70eb0c5-9ce3-4cbf-9864-9f5f06a1adb7
{"app":"notification-service"}

✔ No validation issues found when analyzing namespace: routing-demo.
```

The same three Deployments exist with the same `UID` values, the Service still selects on `app` only, and `istioctl analyze` reports no issue.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-02
```

The grader sends real requests from the `tester` pod and reads the responses and the configuration of the proxy.

---

## Mistakes That Fail The Grader

- **`redirect` and `route` on the same rule (item 2).** They are alternatives, and Istio rejects the object.
- **Putting the default rule first (items 2, 3 and 7).** `/legacy` and `/beta` become unreachable, and no tool reports an error.
- **Looking for the rewrite in an access log (item 3).** The log shows the original path by design. Check `prefixRewrite`.
- **Putting `headers` or `corsPolicy` on only one serving rule (items 4 to 6).** Both serving rules need them.
- **Writing `remove` as a map (item 5).** It is a list of header names.
- **Writing `allowOrigins: ["https://shop.example.com"]` (item 6).** The field takes string matches. Use `exact:`.
- **Assuming `rewrite.uri: /` replaces the whole path (item 3).** After a `prefix` match it replaces only the matched prefix.
