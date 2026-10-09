# Solution Walkthrough

You create two objects: a `DestinationRule` and a `VirtualService`. The rule order matters, as always, but most of the work is in fields *next to* `route`, not inside it. The hardest step is proving the rewrite, because no access log shows it.

---

## Step 1: Read the Starting State

```sh
kubectl -n routing-demo get pods --show-labels
kubectl -n routing-demo get destinationrule,virtualservice
```

```text
notification-service-v1-7d4c9b6f8d-x2mkq   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-6f8b7c5d94-lq7rn   2/2   Running   app=notification-service,version=v2,...
tester-5c7d8f9b6c-8vzpl                    2/2   Running   app=tester,...
No resources found in routing-demo namespace.
```

Nothing configured. The application serves everything at `/notify` and will never learn about `/legacy` or `/beta`.

---

## Step 2: Define the Subsets

Task 3 routes to `v2`, so the subset names have to exist first.

Write the manifest to a file and apply the file. You can then read it again, edit it and apply it again.

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

```sh
astrona submit
```

Expect a failure that names the missing `VirtualService`. A `DestinationRule` only names the subsets; it routes no traffic by itself.

---

## Step 3: The Redirect Rule, First

The sidecar proxy (Envoy) of the client must answer `/legacy` itself and not forward it. A rule with `redirect` has **no** `route`: Istio rejects an object that has both.

```yaml
- match:
    - uri:
        prefix: /legacy
  redirect:
    uri: /notify
    redirectCode: 301
```

It goes first because the rules below it are broader. Put the catch-all above it and `/legacy` never gets its 301. No tool reports an error for that.

---

## Step 4: The Rewrite Rule

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

`rewrite.uri` replaces **only the matched prefix**, so `/beta/notify` becomes `/notify` and reaches an application that has never heard of `/beta`.

---

## Step 5: Headers And CORS On Every Serving Rule

`headers` and `corsPolicy` belong to one rule, not to the whole object. The redirect rule needs neither, because nothing is forwarded and the proxy writes the 301 itself. But **both** rules that route requests need them:

```yaml
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
```

Two details worth getting right: `remove` is a **list of header names**, not a map, and `allowOrigins` takes string matches, so an origin is `exact: <url>` rather than a bare string.

Apply the whole object.

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
    - match:
        - uri:
            prefix: /beta
      rewrite:
        uri: /
      headers:
        request:
          remove: [x-internal-token]
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods: [GET, POST]
      route:
        - destination:
            host: notification-service
            subset: v2
    - headers:
        request:
          remove: [x-internal-token]
        response:
          set:
            x-served-by: notification
      corsPolicy:
        allowOrigins:
          - exact: https://shop.example.com
        allowMethods: [GET, POST]
      route:
        - destination:
            host: notification-service
            subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-notification-service.yaml
```

---

## Step 6: Verify With Live Traffic

```sh
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'legacy: %{http_code} -> %{redirect_url}\n' http://notification-service/legacy/anything
kubectl -n routing-demo exec deploy/tester -- curl -s http://notification-service/beta/notify; echo
kubectl -n routing-demo exec deploy/tester -- curl -s -X POST http://notification-service/notify; echo
kubectl -n routing-demo exec deploy/tester -- \
  curl -s -D - -o /dev/null -H "Origin: https://shop.example.com" -X POST http://notification-service/notify \
  | grep -i 'x-served-by\|access-control-allow-origin'
```

```text
legacy: 301 -> http://notification-service/notify
["EMAIL","SMS"]
["EMAIL"]
x-served-by: notification
access-control-allow-origin: https://shop.example.com
```

`/beta` reaching `v2` and an ordinary `/notify` reaching `v1` is the rule order working.

---

## Step 7: Prove The Rewrite From The Route Table

This is the step that catches people. Istio's access log format is `%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%`, so when Envoy rewrites a path it logs the **original** one. A correct rewrite therefore looks like no rewrite at all in every log you can reach.

The compiled route is the evidence:

```sh
istioctl proxy-config routes deploy/tester -n routing-demo -o json \
  | grep -E '"/beta"|prefixRewrite'
```

```text
"prefix": "/beta",
"prefixRewrite": "/",
```

The matched prefix and its replacement sit on the same route entry. The grader checks this, because it is the only reliable proof available.

---

## Step 8: Submit

```sh
astrona submit
```

---

## Common Mistakes

* **`redirect` and `route` on the same rule.** They are alternatives. Istio rejects the object.
* **Putting the catch-all first.** `/legacy` and `/beta` become unreachable, with no error anywhere.
* **Expecting the rewrite in an access log.** It reports the original path by design. Check `prefixRewrite`.
* **`remove` written as a map.** It is a list of header names.
* **`allowOrigins: ["https://shop.example.com"]`.** The field takes string matches, so use `exact:`.
* **Putting `headers` on only one serving rule.** Every response leaving the service must carry the header, so both serving rules need it.
* **Assuming `rewrite.uri: /` replaces the whole path.** After a `prefix` match it replaces only the matched prefix.
