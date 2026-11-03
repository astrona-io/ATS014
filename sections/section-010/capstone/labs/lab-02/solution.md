# Solution

The walkthrough follows the task from top to bottom, and each section ends with a check. Items 1 to 4 create the four objects. Items 5, 6 and 7 are results of those objects, so you check them after the objects exist. Apply the `DestinationRule` and the delegates before the root, so the root never points at an object that does not exist.

## Start

Look at the starting state:

```bash
kubectl get pods -A -l 'app in (probe,shuttle)'
kubectl get virtualservice,destinationrule -A
```

The `probe` runs in `starfleet`, and a `shuttle` runs in each of the three namespaces. No Istio traffic object exists. Send 10 requests from the `shuttle` in `dock` and read the pod names:

```bash
kubectl -n dock exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

Both versions answer. A client in `dock` uses the full host name, because a short name resolves in the client's own namespace.

## Item 1: the DestinationRule

> **Task item 1:** A `DestinationRule` named **`probe`** for the host `probe` defines the subsets **`v1`** and **`v2`** over the pod label `version`. Its `exportTo` list holds exactly the own namespace and **`dock`**.

The subsets must reach `dock`, so the `DestinationRule` needs the same `exportTo` list as the root. Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  exportTo:
  - "."
  - dock
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Apply it and check the list:

```bash
kubectl apply -f destinationrule-probe.yaml
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.exportTo}{"\n"}'
```

## Item 3: the `probe-hostname` delegate

> **Task item 3:** A delegate named **`probe-hostname`** has no `hosts` and no `gateways`. Its first rule matches the header **`x-canary`** with the exact value **`true`** and routes to subset **`v2`**. Its second rule has no match and routes to subset **`v1`**.

The task lists the root as item 2, and the root needs the delegates, so this walkthrough creates the delegates first. Save this as `virtualservice-probe-hostname.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe-hostname
  namespace: starfleet
spec:
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```bash
kubectl apply -f virtualservice-probe-hostname.yaml
```

## Item 4: the `probe-delay` delegate

> **Task item 4:** A delegate named **`probe-delay`** has no `hosts` and no `gateways`. Its first rule matches the header `x-canary` with the exact value `true`, sets a **timeout of `6s`** and routes to `v2`. Its second rule has no match, sets a **timeout of `2s`** and routes to `v1`.

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
    - headers:
        x-canary:
          exact: "true"
    timeout: 6s
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - timeout: 2s
    route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```bash
kubectl apply -f virtualservice-probe-delay.yaml
```

## Item 2: the root VirtualService

> **Task item 2:** A root `VirtualService` named **`probe`** for the host `probe` has the **same `exportTo` list** and **exactly three rules**, in this order: URI prefix **`/hostname`** delegates to `probe-hostname`; URI prefix **`/delay`** delegates to `probe-delay`; and a last rule with no match sends everything else to subset `v1` on port `8000`.

The root narrows each delegate with its URI prefix. The header rule inside the delegate adds a second condition, and a request must satisfy both. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  exportTo:
  - "."
  - dock
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

Apply it and check for problems:

```bash
kubectl apply -f virtualservice-probe.yaml
istioctl analyze -n starfleet
```

## Item 5: the header and the path

> **Task item 5:** From the `shuttle` in `starfleet` and from the `shuttle` in `dock`, ten requests to `/hostname` **with** the header are all answered by `probe-v2`, and ten requests **without** the header are all answered by `probe-v1`. The client in `dock` calls the host `probe.starfleet.svc.cluster.local`.

Wait a few seconds so `istiod` can push the routes. Then send the requests from `dock`:

```bash
kubectl -n dock exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s -H "x-canary: true" http://probe.starfleet.svc.cluster.local:8000/hostname; done'
kubectl -n dock exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

The first command returns only `probe-v2` pod names, and the second returns only `probe-v1` pod names. Run the same two commands in `starfleet` with the host `probe`:

```bash
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s -H "x-canary: true" http://probe:8000/hostname; done'
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe:8000/hostname; done'
```

## Item 6: the timeouts

> **Task item 6:** From both clients, `/delay/4` **with** the header returns `200`, `/delay/4` **without** the header returns `504`, and `/delay/1` without the header returns `200`.

Print the status code and the time of each request. This is the version for `starfleet`. In `dock`, use `-n dock` and the host `probe.starfleet.svc.cluster.local`:

```bash
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code} %{time_total}\n' -H 'x-canary: true' http://probe:8000/delay/4
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://probe:8000/delay/4
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://probe:8000/delay/1
```

The first request returns `200` after about 4 seconds, because the canary timeout is 6 seconds. The second returns `504` after about 2 seconds. The third returns `200`.

## Item 7: `depot` is unaffected

> **Task item 7:** The `shuttle` in **`depot`** is not affected by these objects. Its request to `/delay/4` without the header returns `200` (no timeout), and its requests to `/hostname` with the header are not all answered by `probe-v2`.

The root and the `DestinationRule` are exported to `starfleet` and `dock` only, so the proxy in `depot` never received them. Check from `depot`:

```bash
kubectl -n depot exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe.starfleet.svc.cluster.local:8000/delay/4
kubectl -n depot exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -H "x-canary: true" http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

The first request returns `200` after about 4 seconds. The second command returns pod names of both versions, because the header means nothing to a proxy without the rules.

## Item 8: Leave the workloads alone

> **Task item 8:** Leave the Deployments and the Service unchanged, and create no Istio object in `dock` or `depot`.

You created objects in `starfleet` only. Check the other two namespaces:

```bash
kubectl get virtualservice,destinationrule -n dock
kubectl get virtualservice,destinationrule -n depot
```

Both commands report that no resources exist.

## Submit

```bash
astrona submit -c sections/section-010/capstone/labs/lab-02
```

## Mistakes That Fail The Grader

- **A `hosts` or `gateways` field on a delegate** (items 3 and 4). A delegate has neither.
- **A different `exportTo` list on the two objects** (items 1 and 2). If the root reaches `dock` and the `DestinationRule` does not, requests from `dock` fail with `503 NC`. A list with `"*"` sends `depot` to the canary rules too.
- **The timeout on the root** (items 4 and 6). The two timeouts depend on the header, so they belong in the `probe-delay` delegate.
- **The header rule last** (items 3 and 4). Rules are read from top to bottom, and a rule with no match first catches everything.
- **A number or order of root rules that differs from the task** (item 2). The grader compares the rules in order.
- **Header value `True` or a boolean** (items 3 and 4). The value is the exact string `"true"`, so quote it in YAML.
- **Using the short host name in `dock`** (items 5 and 6). A client in `dock` must call `probe.starfleet.svc.cluster.local`.
- **Creating Istio objects in `dock` or `depot`** (item 8). The grader fails when it finds one.
