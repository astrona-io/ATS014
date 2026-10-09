# Match Text With Exact, Prefix And Regex

A routing rule that looks right can still send requests to the wrong place. A common cause is that the rule compares text in a different way than you meant. This part shows the three ways a match compares text, and how YAML can change a value before Istio ever sees it.

A **`VirtualService`** is the Istio object that sets where requests to a host go. Its `http` field is an ordered list of rules, and each rule can have a `match` that says which requests it applies to. The **sidecar proxy** (Envoy) of the client pod reads these rules and picks the destination before the request leaves the pod.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground. A subset is a named group of pods, picked by a pod label such as `version: v2`. The commands also use the `count_versions` helper, which sends 10 requests from the `shuttle` pod to `scout` and counts which version answered. `$SCOUT` holds `http://scout:9080/reviews`. Paste the helper into your terminal if it is not there yet:

<!-- astrona:playground:renew -->

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c; }
SCOUT=http://scout:9080/reviews
```

## The three ways to compare text

Every text comparison in a match uses one of three forms, called a **string match**. `headers`, `uri`, `queryParams` and `authority` all use them. Picking the right form is most of the work:

| Form | Matches | Example |
| --- | --- | --- |
| `exact: jason` | exactly `jason`, letter for letter | `jason`, but not `jasonx` or `Jason` |
| `prefix: ja` | anything that starts with `ja` | `jason`, `jane` |
| `regex: "jason\|jane"` | an RE2 pattern that must fit the **whole** value | `jason`, `jane`, but not `jasonx` |

A **regex** (regular expression) is a text pattern: `jason|jane` means "jason or jane". Istio uses the **RE2** syntax for regular expressions, which is the syntax Envoy supports.

Three surprises hide in this table:

- **`prefix` ignores `/`.** It compares plain text. So `prefix: "/reviews"` matches `/reviews` and `/reviews/0`, but also `/reviewsXYZ`.
- **`regex` must fit the whole value.** It works as if the pattern started at the first character and ended at the last. So `regex: "jason"` does not match `jasonx`. For "contains jason", write `.*jason.*`. This is not like `grep`, which finds a word anywhere in a line.
- **RE2 leaves some features out.** Look-ahead (`(?=`) and back-references (`\1`) are missing, because they can make a pattern run for a very long time. Istio rejects a pattern that uses them.

So which form should you pick? **`exact`** cannot surprise you, so use it by default for a header or a query value. **`prefix`** fits a group of paths you own, or a group of user names that start the same way. **`regex`** is the last choice, for rules the other two cannot express. It is the hardest to read and the easiest to get slightly wrong.

`method` uses the same forms: `method: { exact: POST }`.

### Prefix and regex side by side

Start with a prefix: every user whose name starts with `ja` gets v2.

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          prefix: ja
    route:
    - destination:
        host: scout
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```sh
count_versions -H "end-user: jane" $SCOUT/0
count_versions -H "end-user: bob" $SCOUT/0
```

You should see:

```text
  10 scout-v2
  10 scout-v1
```

The value `jane` starts with `ja`, so the proxy sends those requests to v2. The value `bob` does not, so those requests fall through to v1.

Now try a regular expression instead. Save this as `virtualservice-scout.yaml`, replacing the old file:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          regex: "jason|jane"
    route:
    - destination:
        host: scout
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```sh
count_versions -H "end-user: jane" $SCOUT/0
count_versions -H "end-user: jasonx" $SCOUT/0
```

You should see:

```text
  10 scout-v2
  10 scout-v1
```

`jane` still gets v2. `jasonx` gets v1, because the pattern must fit the whole value and the extra `x` does not fit.

## Quoting, and the YAML trap underneath it

Some values look like text to you but not to YAML. If you quote every value, this trap can never catch you.

`exact: true` and `exact: "true"` are different. Without quotes, YAML reads `true` as a boolean (a yes or no value), not as text. The field expects text, so the Kubernetes API server rejects the object. That is the good outcome: you find out at once.

The same goes for numbers. `exact: 2` is a number, not the text `"2"`. Older YAML rules also read bare `yes`, `no`, `on` and `off` as booleans, and a version like `1.30` becomes the number `1.3`. Quote every header and query value, and none of this can happen.

### Match a query parameter

A **query parameter** is a name and a value after the `?` in a URL, such as `canary=true`. This rule sends every request with `?canary=true` to v3.

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - queryParams:
        canary:
          exact: "true"
    route:
    - destination:
        host: scout
        subset: v3
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```sh
count_versions "$SCOUT/0?canary=true"
count_versions $SCOUT/0
```

You should see:

```text
  10 scout-v3
  10 scout-v1
```

Requests with `?canary=true` go to v3, and the others go to v1. A query parameter is useful when the client cannot add headers, for example a link someone clicks in a browser.

To see the quoting trap for yourself, remove the quotes around `"true"` in `virtualservice-scout.yaml` and apply it again. The API server rejects the object, so it never reaches a proxy.

## What you know now

A string match is `exact`, `prefix` or `regex`. `prefix` ignores `/`, and `regex` must fit the whole value. You can match on a header and on a query parameter, and you quote every value so YAML keeps it as text. The open question is what happens when one item in a `match` holds two conditions: must both be true, or is one enough?

## Common pitfalls

> [!WARNING]
> - **Expecting `prefix` to respect `/`.** It does not. `prefix: "/reviews"` also matches `/reviewsXYZ`.
> - **A `regex` that does not cover the whole value.** `regex: "jason"` does not match `jasonx`. Write `.*jason.*` for "contains".
> - **Leaving values unquoted.** `true`, `yes`, `off` and `1.30` are not text to a YAML parser. Quote every header and query value.
