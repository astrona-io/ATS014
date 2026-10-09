# Read A Compiled Match In The Route Table

YAML indentation is easy to misread, so a `match` you wrote as AND can turn out to be OR, or the other way around. The proxy's own copy of your rules is not open to that doubt. This part reads that copy, so you can prove how the proxy understood a rule.

A **`VirtualService`** is the Istio object that sets where requests to a host go. Its `http` field is an ordered list of rules, and each rule can have a `match`. Inside a `match`, conditions in one `-` item are combined with AND, and separate `-` items are combined with OR. The **sidecar proxy** (Envoy) of the client pod reads these rules and picks the destination before the request leaves the pod.

`istiod`, Istio's control plane, turns every rule into one or more **route entries** and sends them to each proxy. You can list them with `istioctl proxy-config routes`. When a rule does not behave the way you read it, this list is the final answer, because it is what the proxy actually runs.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground. A subset is a named group of pods, picked by a pod label such as `version: v2`.

## Two versions of one rule

You need two versions of the same `VirtualService` to compare. The first one sends requests to v2 only when the header `end-user` is `jason` **and** the path starts with `/reviews/1`.

<!-- astrona:playground:renew -->

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

The second one has a `-` in front of `uri`, so it sends requests to v2 when **either** condition is true. Keep it in a second file.

Save this as `virtualservice-scout-or.yaml`:

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

Both files are only saved so far. The steps below apply them one after the other.

## Reading a compiled match

The route table gives two kinds of proof. The number of route entries tells you whether a rule is AND or OR, and the JSON form shows every test inside one entry.

### Count the route entries

Apply the AND version first. It is in `virtualservice-scout.yaml`:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then list the route entries the proxy of `shuttle` holds for port 9080:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080
```

You should see this (shortened to the `scout` rows):

```text
NAME     VHOST NAME                                  DOMAINS                                                     MATCH           VIRTUAL SERVICE
9080     scout.starfleet.svc.cluster.local:9080      scout.starfleet.svc.cluster.local., scout + 2 more...       /reviews/1*     scout.starfleet
9080     scout.starfleet.svc.cluster.local:9080      scout.starfleet.svc.cluster.local., scout + 2 more...       /*              scout.starfleet
```

Each row is one route entry, and the proxy checks them from the top. Two rules in your YAML give two rows. Row 1 is the `jason` rule: the `MATCH` column only shows the path, `/reviews/1*`, but the header test is there too. Row 2 is the catch-all, and `/*` means "every path".

Now apply the OR version:

```sh
kubectl apply -f virtualservice-scout-or.yaml
```

Then list the route entries again:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080
```

You should see this (shortened to the `scout` rows):

```text
NAME     VHOST NAME                                  DOMAINS                                                     MATCH           VIRTUAL SERVICE
9080     scout.starfleet.svc.cluster.local:9080      scout.starfleet.svc.cluster.local., scout + 2 more...       /*              scout.starfleet
9080     scout.starfleet.svc.cluster.local:9080      scout.starfleet.svc.cluster.local., scout + 2 more...       /reviews/1*     scout.starfleet
9080     scout.starfleet.svc.cluster.local:9080      scout.starfleet.svc.cluster.local., scout + 2 more...       /*              scout.starfleet
```

There are three rows now, from the same two rules. `istiod` turned the OR rule into **two** route entries, one per `-` item. The first is "`jason` on any path" (`/*` plus the header test), and the second is "any request to `/reviews/1`". Both send to v2. The last row is still the catch-all.

So the count tells you how the proxy read your `match`. One entry for the rule means AND. One entry per `-` item means OR.

### Look inside one entry

The table hides the header test. To see it, print the same route table as JSON. Apply the AND version again first:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then print the route table as JSON:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json
```

The output is long. These are the two `scout` entries in it, shortened to the parts that matter:

```text
{
  "match": {
    "prefix": "/reviews/1",
    "caseSensitive": true,
    "headers": [
      {
        "name": "end-user",
        "stringMatch": {
          "exact": "jason"
        }
      }
    ]
  },
  "cluster": "outbound|9080|v2|scout.starfleet.svc.cluster.local"
}
{
  "match": {
    "prefix": "/"
  },
  "cluster": "outbound|9080|v1|scout.starfleet.svc.cluster.local"
}
```

The first entry has the path `/reviews/1` **and** the header `end-user` with the exact value `jason` inside **one** `match`, so both must fit. It sends to the v2 cluster. A cluster is Envoy's name for a destination with its list of pod addresses. The second entry is the catch-all to the v1 cluster. The exact field names can change between Envoy versions, but this shape stays the same.

## What you know now

`istiod` turns each `match` item into its own route entry. One entry for a rule means its conditions are combined with AND. One entry per `-` item means OR. The JSON form of the route table also shows the header tests that the table view hides. The open question is what happens when more than one rule matches the same request.

## Common pitfalls

> [!WARNING]
> - **Trusting the `MATCH` column alone.** It shows only the path. The header test is there too, but you see it only in the JSON output.
> - **Reading the YAML instead of the proxy.** When a rule does not behave the way you read it, count its route entries in `istioctl proxy-config routes`.
> - **Expecting exact JSON field names.** They can change between Envoy versions. Look for the shape: one `match` that holds the path and the header together.
