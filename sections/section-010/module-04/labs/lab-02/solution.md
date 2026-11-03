# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The cause is one field: `exportTo` decides which namespaces receive an object. Items 1 and 2 fix the field on the two objects, and items 3 to 6 prove the result.

---

## Start: Read The Starting State

Read the two objects. Look at the `exportTo` field of each:

```sh
kubectl -n starfleet get virtualservice probe -o yaml
kubectl -n starfleet get destinationrule probe -o yaml
```

Both objects have `exportTo` with the single value `"."`. The value `"."` means the object's own namespace. The default is `"*"`, every namespace. So only the proxies in `starfleet` receive these two objects.

Prove the problem with the `shuttle` in `dock`. A short host name resolves in the client's own namespace, so the client in `dock` uses the full host name:

```sh
kubectl -n dock exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

You read pod names of both `probe-v1` and `probe-v2`. The proxy in `dock` never received the `VirtualService`, so it sends requests to the plain Service. You can see the same fact in the cluster list of that proxy:

```sh
istioctl proxy-config clusters deploy/shuttle -n dock --fqdn probe.starfleet.svc.cluster.local
```

The list has the cluster for the Service port, and it has no cluster for the subset `v2`.

---

## Item 1 and item 2: Export both objects to `dock`

> **Task item 1:** The `VirtualService` `probe` is visible in its own namespace and in **`dock`**, and in no other namespace. Its `exportTo` list holds exactly those two namespaces.

> **Task item 2:** The `DestinationRule` `probe` has the **same `exportTo` list**. Without it, requests from `dock` fail even though the `VirtualService` is visible.

These two items share one section, because the two objects must change together. A `VirtualService` that routes to the subset `v2` needs the `DestinationRule` that defines `v2` in the same proxy. If the proxy in `dock` receives only the `VirtualService`, it has a route to a cluster that does not exist, and requests fail with `503` and the response flag `NC` (no cluster). You can try it: change only the `VirtualService` first, and read the `dock` proxy's access log. Then fix both.

Save this as `destinationrule-probe.yaml`:

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

Save this as `virtualservice-probe.yaml`:

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
  - route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
```

Apply both files:

```sh
kubectl apply -f destinationrule-probe.yaml
kubectl apply -f virtualservice-probe.yaml
```

Then check the two lists:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.exportTo}{"\n"}'
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.exportTo}{"\n"}'
```

Both commands print a list with `.` and `dock`.

---

## Item 3: `dock` reaches only `v2`

> **Task item 3:** Ten requests from the `shuttle` in `dock` to `http://probe.starfleet.svc.cluster.local:8000/hostname` are **all answered by `probe-v2`**.

Wait a few seconds, so `istiod` can push the objects to the proxy in `dock`. Then send 10 requests:

```sh
kubectl -n dock exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

Every answer carries a `probe-v2` pod name. The cluster list of the `dock` proxy now has a cluster for the subset `v2`:

```sh
istioctl proxy-config clusters deploy/shuttle -n dock --fqdn probe.starfleet.svc.cluster.local
```

---

## Item 4: `starfleet` still reaches only `v2`

> **Task item 4:** Ten requests from the `shuttle` in `starfleet` to `http://probe:8000/hostname` are still all answered by `probe-v2`.

Adding `dock` to the list does not remove the own namespace, because the list keeps the `"."`:

```sh
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 10); do curl -s http://probe:8000/hostname; done'
```

All 10 answers come from `probe-v2`.

---

## Item 5: `depot` keeps the default behaviour

> **Task item 5:** The `shuttle` in **`depot`** keeps the default behaviour: its requests are still spread over both versions. Do not export either object to `depot`, and do not add a `VirtualService` there.

You made no change for `depot`, and its name is not in either list. Send 20 requests from there:

```sh
kubectl -n depot exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s http://probe.starfleet.svc.cluster.local:8000/hostname; done'
```

You read pod names of both versions. A list with `"*"` instead of the two names would send `depot` to `v2` as well, and it would fail this item.

---

## Item 6: Leave the workloads alone

> **Task item 6:** Leave the Deployments and the Service unchanged. Do not delete and recreate the two objects with another name.

You changed only the `exportTo` field of the two existing objects. Check that the namespaces `dock` and `depot` hold no Istio objects of their own:

```sh
kubectl -n dock get virtualservice,destinationrule
kubectl -n depot get virtualservice,destinationrule
```

Both commands report that no resources exist.

---

## Submit

```sh
astrona submit -c sections/section-010/module-04/labs/lab-02
```

---

## Mistakes That Fail The Grader

- **Exporting only the `VirtualService`** (item 2). The proxy in `dock` then has a route to a subset it does not know, and requests fail with `503 NC`.
- **Exporting only the `DestinationRule`** (item 1). The `VirtualService` stays hidden, so `dock` still reaches both versions.
- **Using `"*"` or leaving `exportTo` out** (items 1, 2 and 5). Every namespace receives the objects, and `depot` goes to `v2`.
- **Writing `dock` without `"."`** (items 1 and 4). The list must keep the own namespace, or `starfleet` loses the rules. The grader accepts `starfleet` in place of `"."`.
- **Creating a copy of the objects in `dock`** (items 1 and 6). The grader fails when `dock` or `depot` hold Istio objects.
- **Using the short host name in `dock`** (item 3). A client in `dock` must call `probe.starfleet.svc.cluster.local`.
