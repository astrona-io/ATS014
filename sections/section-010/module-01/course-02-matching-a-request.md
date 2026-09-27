# Part 2 — Matching A Request

> Prerequisite: [Part 1 — Subsets And The Destination Vocabulary](./course-01-subsets-and-destination-vocabulary.md). Next: [Part 3 — Evaluation Order, Name Resolution And Proof](./course-03-evaluation-order-and-proof.md).

Part 1 gave you named destinations. This part is about the other half of a routing rule: the description of *which requests* it applies to. The `match` block is a small language, and nearly all of the mistakes people make with it come from two things — choosing the wrong string-comparison form, and misreading whether two conditions must both hold. This part settles both.

## The shape of one rule

A `VirtualService` holds a list under `http`. Each entry is one rule with two halves:

```yaml
http:
  - match:                      # WHICH requests — optional
      - headers:
          testing:
            exact: "true"
    route:                      # WHERE they go — required
      - destination:
          host: notification-service
          subset: v2
```

`route` names a destination from Part 1's vocabulary — the `subset: v2` resolves only because a `DestinationRule` defined it. `match` is optional, and a rule without one matches everything; Part 3 is about what that implies.

Underneath, this compiles into an Envoy **route entry**: a match predicate plus the name of the cluster to send matching requests to. The `proxy-config routes` output you will meet in Part 3 is that compiled form.

## Four things you can match on

| Match type | Matches against | Note |
| --- | --- | --- |
| `headers` | a named request header | header names are matched case-insensitively; values are not |
| `uri` | the request path | the path only — the query string is *not* part of it |
| `queryParams` | one named query parameter | matched after the path is split at `?` |
| `method` | the HTTP verb | `GET`, `POST`, … |

Two of those have a subtlety worth stating now, because each produces a rule that looks right and never fires.

**`uri` does not include the query string.** A request for `/notify?version=2` has a `uri` of `/notify`. Writing `uri: { exact: "/notify?version=2" }` matches nothing, ever. Query matching is `queryParams`' job, and it is a separate key for exactly this reason.

**Header names are conventionally lowercase.** HTTP/2 mandates lowercase header names, and Envoy normalises HTTP/1 headers to lowercase before matching, so `testing`, `Testing` and `TESTING` all work as the *key*. The **value** is compared literally — `exact: "true"` does not match a header whose value is `True`.

There are further match keys — `authority` (the `Host` header), `scheme`, `port`, and `sourceLabels` (the labels of the *calling* workload, which section 080 uses) — but the four above are the ones this module's task is built from.

## The three string forms

`headers`, `uri`, `queryParams` and `authority` all take the same small choice of comparison, called a **string match**:

| Form | Semantics | Example that matches `/notify/beta/42` |
| --- | --- | --- |
| `exact` | the whole value, character for character | `exact: "/notify/beta/42"` |
| `prefix` | the value starts with this string | `prefix: "/notify"` |
| `regex` | an **RE2** regular expression against the whole value | `regex: "^/notify/.*$"` |

Three things to hold on to:

- **`prefix` is a plain string prefix.** `prefix: "/notify"` matches `/notify`, `/notify/beta` **and** `/notifyXYZ`. This is worth noting now because the Kubernetes `Ingress` API's `pathType: Prefix` is *element-wise* and does not match `/notifyXYZ` — the two APIs use the same word for different behaviour, and section 060 makes you translate between them.
- **`regex` is RE2, not PCRE.** RE2 is Google's linear-time regex engine. It deliberately omits backreferences and lookahead/lookbehind, because those are what make a regex able to blow up exponentially on hostile input. A pattern using `(?=`, `(?!` or `\1` will be rejected by the control plane rather than silently misbehaving.
- **`regex` is anchored against the whole value.** Envoy matches the complete string, so `regex: "beta"` does **not** match `/notify/beta`; you want `regex: ".*beta.*"` or an anchored `^/notify/.*$`.

`method` is the odd one out: it takes a string match applied to the verb, written directly as `method: { exact: POST }`.

> [!TIP]
> **Try it — one header rule, and the request that misses it**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: notification-service
>   namespace: routing-demo
> spec:
>   hosts:
>     - notification-service
>   http:
>     - match:
>         - headers:
>             testing:
>               exact: "true"
>       route:
>         - destination:
>             host: notification-service
>             subset: v2
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1
> EOF
> kubectl -n routing-demo exec deploy/tester -- \
>   curl -s -X POST -H "testing: true"  http://notification-service/notify
> kubectl -n routing-demo exec deploy/tester -- \
>   curl -s -X POST -H "TESTING: true"  http://notification-service/notify
> kubectl -n routing-demo exec deploy/tester -- \
>   curl -s -X POST -H "testing: True"  http://notification-service/notify
> ```
>
> Expect something like:
>
> ```text
> ["EMAIL","SMS"]
> ["EMAIL","SMS"]
> ["EMAIL"]
> ```
>
> The first two are the same request as far as matching is concerned — the header *name* is case-insensitive. The third falls through to the default rule because the header *value* `True` is not the string `true`. That third line is the entire argument for quoting values and being literal about them.

## Quoting, and the YAML trap underneath it

`exact: true` and `exact: "true"` are different documents. Unquoted `true` is a YAML **boolean**; the field wants a string, so the apply is rejected — which is the good outcome, because you find out immediately.

The dangerous version is numeric. `exact: 2` parses as an integer and is likewise rejected by the schema, but the habit of leaving values unquoted eventually produces something that *is* a valid string and still wrong: YAML's older rules treat bare `yes`, `no`, `on` and `off` as booleans too. Quote every header and query value and none of this can reach you.

## AND or OR: the rule that depends on indentation

This is the single most misread part of the object, and it is decided entirely by where an item sits in the list.

```yaml
match:
  - headers:                 # ┐ entry 1
      testing:               # │  header AND uri must BOTH hold
        exact: "true"        # │
    uri:                     # │
      prefix: /notify/beta   # ┘
  - queryParams:             # ┐ entry 2 — ORed with entry 1
      version:               # │
        exact: "2"           # ┘
```

The rule:

- **Conditions inside one `-` entry are ANDed.** Every condition in that entry must hold.
- **Separate `-` entries are ORed.** The rule fires if any entry matches.

So the block above reads: *(header `testing: true` **AND** path starting `/notify/beta`) **OR** query `version=2`*.

The failure this causes is quiet in both directions. Collapsing three intended alternatives into one entry produces a rule that needs all three at once and therefore almost never fires. Splitting an intended conjunction into separate entries produces a rule far broader than you meant — which does fire, on traffic you did not intend to divert.

> [!TIP]
> **Try it — the same three conditions, ANDed then ORed**
>
> ```sh
> kubectl -n routing-demo patch virtualservice notification-service --type merge -p '
> spec:
>   http:
>     - match:
>         - headers:
>             testing:
>               exact: "true"
>           uri:
>             prefix: /notify/beta
>       route:
>         - destination:
>             host: notification-service
>             subset: v2
>     - route:
>         - destination:
>             host: notification-service
>             subset: v1'
> echo "--- ANDed: header alone, path alone, then both ---"
> kubectl -n routing-demo exec deploy/tester -- curl -s -X POST -H "testing: true" http://notification-service/notify
> kubectl -n routing-demo exec deploy/tester -- curl -s -X POST http://notification-service/notify/beta
> kubectl -n routing-demo exec deploy/tester -- curl -s -X POST -H "testing: true" http://notification-service/notify/beta
> ```
>
> Expect something like:
>
> ```text
> --- ANDed: header alone, path alone, then both ---
> ["EMAIL"]
> ["EMAIL"]
> ["EMAIL","SMS"]
> ```
>
> Two `v1` answers and one `v2`: neither condition alone is enough. Split the same two conditions onto separate `-` entries and re-run — all three lines become `["EMAIL","SMS"]`, because now either one suffices. Nothing but indentation changed.

## Reading a compiled match

Because a match compiles to an Envoy route entry, you can check your reading of the YAML against what the proxy actually holds. The JSON form of `proxy-config routes` shows the predicate, and it is unambiguous where the YAML is not: ANDed conditions appear as sibling fields of one `match` object, while ORed alternatives appear as separate entries in the `routes` array.

> [!TIP]
> **Try it — the predicate as Envoy stores it**
>
> ```sh
> istioctl proxy-config routes deploy/tester -n routing-demo -o json \
>   | grep -E '"prefix"|"exact_match"|"exactMatch"|"name": "testing"|"path"' | head -12
> ```
>
> Expect something like:
>
> ```text
> "path": "/notify/beta",
> "name": "testing",
> "exactMatch": "true",
> "prefix": "/",
> ```
>
> The header condition and the path condition sit together in one match object — the AND you wrote. The trailing `"prefix": "/"` is the catch-all default rule, which matches every path; Part 3 is about why its position in the list is the most consequential thing in the object.

> *Conditions inside one `-` entry are ANDed; separate `-` entries are ORed — the only difference is indentation.*

## Reference

- [HTTPMatchRequest API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) — every match key, including `authority`, `scheme`, `port` and `sourceLabels`.
- [StringMatch API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#StringMatch) — the `exact` / `prefix` / `regex` choice, in one short page.
- [RE2 syntax](https://github.com/google/re2/wiki/Syntax) — what is and is not available in an Istio `regex`, and why.
- [Request routing task](https://istio.io/latest/docs/tasks/traffic-management/request-routing/) — the upstream walkthrough this module's scenario follows.
