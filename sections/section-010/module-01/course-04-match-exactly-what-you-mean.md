# Match Exactly What You Mean

Astronaut, a routing rule that looks right can still send signals the wrong way. Usually the cause is one of two things: the rule compares text differently from what you meant, or two conditions are combined differently from what you meant. This part settles both.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground, and the `count_versions` helper pasted into your terminal.

## The three ways to compare text

Every text comparison in a match uses one of three forms. Picking the right one is most of the work.

`headers`, `uri`, `queryParams` and `authority` all use the same small choice of comparison, called a **string match**:

| Form | Matches | Example |
| --- | --- | --- |
| `exact: jason` | exactly `jason`, letter for letter | `jason`, but not `jasonx` or `Jason` |
| `prefix: ja` | anything that starts with `ja` | `jason`, `jane` |
| `regex: "jason\|jane"` | an RE2 pattern that must fit the **whole** value | `jason`, `jane`, but not `jasonx` |

A **regex** (regular expression) is a search pattern. `jason|jane` means "jason or jane". **RE2** is the pattern style Istio uses.

Three things to hold on to:

- **`prefix` is a plain text prefix.** It does not care about `/`. `prefix: "/reviews"` matches `/reviews`, `/reviews/0` **and** `/reviewsXYZ`. The Kubernetes `Ingress` API's `pathType: Prefix` does care about `/` and does not match `/reviewsXYZ`. Same word, different rule.
- **`regex` is RE2, not the style many languages use.** RE2 leaves out look-ahead (`(?=`) and back-references (`\1`), because those can make a pattern run for a very long time. Istio rejects a pattern that uses them.
- **`regex` must match the whole value.** It acts as if it had `^...$` around it ("from the first letter to the last"). So `regex: "jason"` does not match `jasonx`. For "contains jason", write `.*jason.*`. People often expect it to work like `grep`, which finds a word anywhere. It does not.

The choice is not about style. `exact` cannot surprise you, so it is the right default for a header or a query value. `prefix` is right for a group of paths you own, or a group of users like `beta-*`. `regex` is the last resort: use it when the others cannot express the rule. It is the hardest to read and the easiest to get subtly wrong.

`method` is written directly with the comparison: `method: { exact: POST }`.

### Prefix and regex side by side

First a prefix: every astronaut whose name starts with `ja` gets v2. Save this as `virtualservice-scout.yaml`:

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

You should see `10 scout-v2` for jane (her name starts with `ja`) and `10 scout-v1` for bob.

Now try a regex instead. Save this as `virtualservice-scout.yaml`, replacing the old file:

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

`jane` still gets v2. `jasonx` gets v1: the extra `x` breaks a whole-value match.

## Quoting, and the YAML trap underneath it

Some values look like text to you but not to YAML. If you quote every value, this trap can never catch you.

`exact: true` and `exact: "true"` are different. Without quotes, YAML reads `true` as a yes/no value (a boolean), not as text. The field wants text, so Istio rejects the object. That is the good outcome: you find out straight away.

The same goes for numbers. `exact: 2` is a number, not the text `"2"`. Older YAML rules also read bare `yes`, `no`, `on` and `off` as yes/no values, and a version like `1.30` becomes the number `1.3`. Quote every header and query value, and none of this can reach you.

### Match a query parameter

Send every signal that asks for `?canary=true` to v3. Save this as `virtualservice-scout.yaml`:

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

You should see `10 scout-v3` for the URL with `?canary=true`, and `10 scout-v1` without it. A query parameter helps when the client cannot set headers, for example a link in a browser. Remove the quotes around `"true"` and apply again: Istio rejects the object.

## AND or OR: the rule that depends on one dash

This is the most misread part of the flight plan. Whether two conditions must both be true, or only one of them, is decided only by where an item sits in the list.

Think of `match` as a **list of lists**. `match` is a list of choices. Each choice is a bundle of conditions that must all be true.

```mermaid
flowchart TB
    Q["request"] --> E1{"item 1"}
    E1 -->|"jason AND /reviews/1"| M["subset v2"]
    E1 -->|"no"| E2{"item 2"}
    E2 -->|"canary = true"| M
    E2 -->|"no"| N["next rule"]
```

Item 1 holds two conditions, `end-user = jason` AND path prefix `/reviews/1`. Item 2 holds one, `canary = true`. The rule matches, and sends the signal to v2, if item 1 is fully true or item 2 is true. Otherwise the proxy moves on to the next `http` rule. Inside an item, every condition must be true. Between items, only one item has to match. The picture shows the whole meaning of `match`.

In YAML, a new item starts with a new `-` at the `match` level. Another condition in the same item is another key lined up under the first one:

```yaml
# AND: one item                      # OR: two items
- match:                             - match:
  - headers:                           - headers:
      end-user: {exact: jason}             end-user: {exact: jason}
    uri: {prefix: /reviews/1}          - uri: {prefix: /reviews/1}
```

The only difference is one `-` in front of `uri`. The rule:

- **Conditions inside one `-` item are combined with AND.** All of them must be true.
- **Separate `-` items are combined with OR.** The rule fires if any item matches.

The mistake is quiet both ways. Squash three choices into one item, and the rule needs all three at once, so it almost never fires. Split one AND into separate items, and the rule fires on far more traffic than you meant. Neither is an error. Both are valid objects that behave differently from the sentence in your head.

Predict the next result before you run it.

### The same two conditions, AND then OR

First the AND version: jason **and** the path `/reviews/1`. Save this as `virtualservice-scout.yaml`:

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
          exact: jason
      uri:
        prefix: /reviews/1
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
count_versions -H "end-user: jason" $SCOUT/0
count_versions -H "end-user: jason" $SCOUT/1
count_versions $SCOUT/1
```

You should see:

```text
  10 scout-v1
  10 scout-v2
  10 scout-v1
```

Only jason on `/reviews/1` gets v2: both conditions must hold.

Now the OR version. The only change is a `-` in front of `uri`. Save this as `virtualservice-scout.yaml`, replacing the old file:

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
          exact: jason
    - uri:
        prefix: /reviews/1
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

Run the same three `count_versions` lines again. Now jason on any path gets v2, and anyone on `/reviews/1` gets v2. Only plain `/reviews/0` stays on v1. Nothing changed but one dash.

## Reading a compiled match

Each match becomes an Envoy route entry, so you can check your reading of the YAML against what the proxy holds. The JSON form of `proxy-config routes` shows the test. It is clear where the YAML is not: AND conditions sit side by side in one `match` object, while OR choices become separate entries in the `routes` list.

Make this a habit. When a rule does not behave the way you read it, the compiled test is the judge. It is what actually runs, and it cannot be misread the way indentation can.

### See the test as Envoy stores it

With the AND version applied, print the route table the shuttle holds, filtered to the match fields:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json \
  | grep -E '"prefix"|"exact"|"name": "end-user"' | head -12
```

With the AND rule applied, look for the path prefix `/reviews/1` and the header name `end-user` with `exact` value `jason` inside the **same** match object. Further down is a `"prefix": "/"`: that is the catch-all rule, which matches every path. The exact JSON field names can change between Envoy versions. The structure is what matters.

## Common pitfalls

> [!WARNING]
> - **Expecting `prefix` to respect `/`.** It does not. `prefix: "/reviews"` also matches `/reviewsXYZ`.
> - **A `regex` that does not cover the whole value.** `regex: "jason"` does not match `jasonx`. Write `.*jason.*` for "contains".
> - **Leaving values unquoted.** `true`, `yes`, `off` and `1.30` are not text to a YAML parser. Quote every header and query value.
> - **Reading AND as OR, or OR as AND.** Conditions inside one `-` item must all hold. Separate `-` items are alternatives.

> *Conditions inside one `-` item are combined with AND. Separate `-` items are combined with OR. The only difference is one dash.*
