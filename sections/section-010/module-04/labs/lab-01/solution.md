# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. You write three `VirtualService` objects. Items 1 and 2 create the two delegates, item 3 creates the root that points at them, and items 4 to 7 prove the result. Apply the delegates before the root, so the root never points at an object that does not exist.

---

## Start: Read The Starting State

Check that the `probe` runs in two versions, that the `DestinationRule` has both subsets, and that no `VirtualService` exists:

```sh
kubectl -n starfleet get pods -L app,version
kubectl -n starfleet get destinationrule,virtualservice
```

The `probe` pods carry a `version` label, and the `DestinationRule` named `probe` is the only Istio object in the namespace. Now send 10 requests to `/hostname` from the `shuttle` pod:

```sh
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe:8000/hostname; done'
```

Without a `VirtualService`, the Service sends requests to both versions, so you read pod names of `probe-v1` and of `probe-v2` in the result.

---

## Item 1: The `probe-hostname` delegate

> **Task item 1:** A delegate `VirtualService` named **`probe-hostname`** has **no `hosts` and no `gateways`**. It sends every request to subset **`v2`** on port `8000`.

A delegate is a `VirtualService` without `hosts` that another `VirtualService` hands part of its routes to. Save this as `virtualservice-probe-hostname.yaml`:

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

Then check that the object has no `hosts`. The command prints an empty line:

```sh
kubectl -n starfleet get virtualservice probe-hostname -o jsonpath='{.spec.hosts}{"\n"}'
```

---

## Item 2: The `probe-delay` delegate

> **Task item 2:** A delegate `VirtualService` named **`probe-delay`** has **no `hosts` and no `gateways`**. It matches requests whose URI starts with **`/delay/`**, sets a **timeout of `2s`**, and sends them to subset **`v1`** on port `8000`.

Save this as `virtualservice-probe-delay.yaml`:

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

Apply it and check the timeout:

```sh
kubectl apply -f virtualservice-probe-delay.yaml
kubectl -n starfleet get virtualservice probe-delay -o jsonpath='{.spec.http[0].timeout}{"\n"}'
```

The second command prints `2s`.

---

## Item 3: The root `VirtualService`

> **Task item 3:** A root `VirtualService` named **`probe`** for the host **`probe`** has **exactly three rules**, in this order: URI prefix **`/hostname`** delegates to `probe-hostname`; URI prefix **`/delay`** delegates to `probe-delay`; and a last rule with no match sends everything else to subset **`v1`** on port `8000`.

The root owns the host. A rule with `delegate` has no `route` of its own, and the last rule has no `match`, so it catches everything the first two rules leave. Save this as `virtualservice-probe.yaml`:

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

Then check that `istioctl analyze` reports no problem for the namespace:

```sh
istioctl analyze -n starfleet
```

---

## Items 4, 5 and 6: Prove the routing with real requests

> **Task item 4:** The `shuttle` pod calls `http://probe:8000/hostname` and **every one of 10 requests** is answered by `probe-v2`.

> **Task item 5:** A request to `http://probe:8000/delay/1` returns `200`, and a request to `http://probe:8000/delay/5` returns **`504`** after about 2 seconds, not after 5.

> **Task item 6:** A request to `http://probe:8000/get` returns `200` every time, not `404`. The last rule of the root must catch it.

These three items share one section, because one set of rules produces all of them. Wait a few seconds after the apply, so `istiod` can push the routes. Then send 10 requests to `/hostname`:

```sh
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe:8000/hostname; done'
```

Every answer carries a `probe-v2` pod name. Next, send the delay requests and print the status code and the time of each:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://probe:8000/delay/1
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://probe:8000/delay/5
```

The first request returns `200` after about 1 second. The second returns `504` after about 2 seconds, because the delegate's timeout ends the request. Last, send a request that matches neither prefix:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe:8000/get
```

It returns `200`: the last rule of the root caught it.

---

## Item 7: Leave the workloads alone

> **Task item 7:** Leave the Deployments, the Service and the `DestinationRule` unchanged.

You only created `VirtualService` objects, so nothing else changed. Confirm that both subsets are still there and that the proxy's route table for port `8000` holds the delegated routes:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.subsets[*].name}{"\n"}'
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

The first command prints `v1 v2`. The route table lists the `/hostname` and `/delay` routes for the host `probe`. `istiod` merged the root and its delegates into this one table.

---

## Submit

```sh
astrona submit -c sections/section-010/module-04/labs/lab-01
```

---

## Mistakes That Fail The Grader

- **Putting `hosts` or `gateways` on a delegate** (items 1 and 2). A delegate has none. The grader reads both fields.
- **Using a `route` and a `delegate` in the same rule** (item 3). Istio does not accept both in one rule.
- **A different order or a different number of rules in the root** (item 3). The grader expects exactly the three rules, in the order of the task.
- **Matching `/delay/` in the root** (item 3). The root's prefix is `/delay`, and the delegate's prefix is `/delay/`. The grader compares both.
- **Forgetting the timeout, or setting it on the root** (item 5). The `504` after 2 seconds comes from `timeout: 2s` in the `probe-delay` delegate.
- **Leaving out the last rule** (item 6). A request to `/get` then gets `404`, because no rule matches it.
- **Sending a delegate to the wrong subset** (items 1 and 4). `probe-hostname` must route to `v2`.
- **Changing the `DestinationRule`** (item 7). The grader checks that both subsets still exist.
