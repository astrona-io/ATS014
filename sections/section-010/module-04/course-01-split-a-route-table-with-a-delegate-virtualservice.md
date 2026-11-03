# Split A Route Table With A Delegate VirtualService

A host has one route table, and a route table is easy to break when many people edit one object. Suppose one team owns the rules for `/hostname` and another team owns the rules for `/delay`. If both edit the same `VirtualService`, each change can break the other team's rules. This part shows how to give each team its own object and still keep one host with one entry point.

The feature is called delegation. A `VirtualService` that owns the host is the root. A rule in the root can name another `VirtualService` as its `delegate`, and that second object supplies the routes for the rule. The second object is the delegate VirtualService.

The commands below need the `probe` `DestinationRule` with the subsets `v1` and `v2` (the playground applies it) and no `VirtualService` for `probe`. First look at what a request does with no routing rule at all. The helper sends 10 requests to `/hostname` from the `shuttle` pod and counts the answering `probe` version:

<!-- astrona:playground:renew -->

```sh
astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/hostname
```

With no `VirtualService`, the sidecar proxy (Envoy) of `shuttle` spreads the requests over the endpoints of the `probe` Service. You should see both `probe-v1` and `probe-v2` in the count.

## A delegate holds routes and no host

A delegate is a normal `VirtualService` with one difference: it has no `hosts` field. Without a host, it does not belong to any host by itself. It only works when a root `VirtualService` points at it by name and namespace. Istio also does not accept `gateways`, `tcp` or `tls` routes in a delegate. A delegate holds `http` rules only.

Make the delegate first, so that the root never points at an object that does not exist yet. Save this as `virtualservice-probe-hostname.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe-hostname
  namespace: starfleet
spec:
  http:
  - route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-hostname.yaml
```

Nothing changes for any request yet. The delegate has no host, so no proxy uses it until a root points at it. Now write the root. It owns the host `probe`. Its first rule matches the path prefix `/hostname` and hands the request to the delegate. Its last rule has no `match`, so it catches everything else. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - match:
    - uri:
        prefix: /hostname
    delegate:
      name: probe-hostname
      namespace: starfleet
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then check the result with the helper. The first command sends requests to the delegated path. The second sends requests to a path that only the last rule of the root matches:

```sh
astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/hostname
astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/get
```

All 10 answers for `/hostname` now come from `probe-v2`, because the delegate routes to subset `v2`. The second command prints `status 200` 10 times: the root's last rule routes `/get` to subset `v1`, and `/get` does not return a pod name.

A rule that uses `delegate` cannot also have `route` or `redirect`. The delegate supplies the routes. Everything else a rule can hold, such as `match`, stays in the root.

## The root match narrows the delegate

The root rule matches the prefix `/hostname`. The delegate rule above has no `match` of its own, so it inherits the root's match. When the delegate rule has a `match`, Istio combines the two. A request must satisfy the root's `match` and the delegate's `match`. The root decides which requests enter the delegate, and the delegate can only narrow that set further.

A second delegate shows this. It handles the path prefix `/delay/` and adds a timeout of 2 seconds. A timeout is the longest time the proxy waits for a response before it answers `504`. Save this as `virtualservice-probe-delay.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe-delay
  namespace: starfleet
spec:
  http:
  - match:
    - uri:
        prefix: /delay/
    timeout: 2s
    route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-delay.yaml
```

The root needs a rule that points at it. Save the new version of the root as `virtualservice-probe.yaml`. It keeps the first rule and the last rule, and adds one rule in between:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - match:
    - uri:
        prefix: /hostname
    delegate:
      name: probe-hostname
      namespace: starfleet
  - match:
    - uri:
        prefix: /delay
    delegate:
      name: probe-delay
      namespace: starfleet
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then check the result. The probe path `/delay/1` waits 1 second, and `/delay/5` waits 5 seconds. The `curl` option `-w` prints the status code and the total time:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://probe:8000/delay/1
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://probe:8000/delay/5
```

The first request gets `200` after about 1 second. The second gets `504` after about 2 seconds, because the delegate's timeout is shorter than the 5 second delay. The delegate's own `match` (`/delay/`) sits inside the root's `match` (`/delay`), so every rule is reachable.

## Read the delegated routes in the proxy

`istiod`, Istio's control plane, merges the root and its delegates into one route table before it sends the table to the proxies. The proxy does not know that delegates exist. Read the table of `shuttle` for port `8000`:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

The table has one row for the match `/hostname*`, one for the delay match, and a last row for the catch-all. The delay row shows the narrower match from the delegate, `/delay/*`, not the root's `/delay*`. That row is the merge of the two objects.

## What delegation cannot do

Delegation has limits that explain most mistakes:

- **One level.** A delegate cannot name another delegate. The root points at delegates, and the chain ends there.
- **HTTP only.** The `delegate` field exists only in `http` rules. A delegate cannot hold `tcp` or `tls` routes.
- **No host and no gateway.** A delegate has no `hosts` and no `gateways`. The host and the gateways belong to the root.
- **A match outside the root's match is lost.** If a delegate rule matches paths that the root rule does not pass on, those requests never reach it.
- **Lookup by name and namespace.** The root finds the delegate with the `name` and `namespace` in its `delegate` field. A wrong name or namespace gives a rule with no routes.

You now know how to split a route table: one root that owns the host, and one delegate for each part that another team changes. The open question is who receives these objects. A `VirtualService` in one namespace is still visible to clients in every other namespace, and that is the topic of the next part.

## Common pitfalls

> [!WARNING]
> - **Adding `hosts` to a delegate.** A `VirtualService` with hosts is a normal object that owns those hosts. Leave `hosts` out of every delegate.
> - **Putting `route` and `delegate` in one rule.** A rule has either a `delegate` or its own `route`. Not both.
> - **A wrong `name` or `namespace` in `delegate`.** Istio finds no delegate, so the rule adds no route. The route table shows the missing match. Check it with `istioctl proxy-config routes`.
> - **Applying the root before the delegate.** For a short time the root points at an object that does not exist. Apply the delegate first.
> - **Expecting a second level.** A delegate that has its own `delegate` rule does not work. Keep the structure one level deep.

## Your mission: Split A Probe Route Table Across Delegates Lab

You can now write a root `VirtualService` and delegate objects, and prove that a request follows the delegated rules. The mission asks you to build a root and two delegates from a short specification, and to prove it with real requests and the proxy's route table.

Pause the playground, then start the lab and submit it:

```sh
astrona stop ats-014-playground-010-04
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-04/labs/lab-01
astrona submit -c sections/section-010/module-04/labs/lab-01
```

When you are done, remove the lab and start the playground again:

```sh
astrona destroy ats-014-lab-010-04-01
astrona start ats-014-playground-010-04
```
