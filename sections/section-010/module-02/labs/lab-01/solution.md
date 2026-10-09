# Solution Walkthrough

The answer is one object with three entries in `hosts`. But the grader checks the proxy's own configuration and sends live requests, so the measurement matters as much as the YAML.

---

## Step 1: Measure The Starting Point

You cannot show that the configuration got smaller without a number to compare against, so take it first. A cluster is a destination in the proxy's configuration, and `istioctl proxy-config cluster` lists them:

```sh
istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -E 'sidecar-other|sidecar-third'
```

```text
      34
httpbin.sidecar-other.svc.cluster.local   8000   -   outbound   EDS
httpbin.sidecar-third.svc.cluster.local   8000   -   outbound   EDS
```

The `tester` proxy holds clusters for both other namespaces. This is the mesh default: `istiod` gives every proxy every host in the service registry.

Confirm that all three destinations answer now:

```sh
for url in http://local-backend:8000/get \
           http://httpbin.sidecar-other:8000/get \
           http://httpbin.sidecar-third:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n sidecar-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
```

```text
http://local-backend:8000/get -> 200
http://httpbin.sidecar-other:8000/get -> 200
http://httpbin.sidecar-third:8000/get -> 200
```

No policy allowed any of these requests. They work because the configuration is there.

---

## Step 2: Write The Sidecar

Write the manifest to a file and apply the file. This habit pays off in the exam: you can read the file again, edit it and apply it again.

Save this as `sidecar-default.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: sidecar-demo
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
        - "sidecar-other/*"
```

Apply it:

```sh
kubectl apply -f sidecar-default.yaml
```

```text
sidecar.networking.istio.io/default created
```

Each part of the object is there for a reason:

- **No `workloadSelector`.** The task says every workload in the namespace, and leaving out the selector is how you say that. A selector for `app: tester` would leave the `local-backend` proxy unchanged, and the grader rejects it.
- **`./*`**: the proxy's own namespace, which keeps `local-backend` reachable.
- **`istio-system/*`**: the control plane and telemetry destinations. Leaving it out causes a partial failure that never points back at this object.
- **`sidecar-other/*`**: the one other namespace you must keep.
- **The name `default`**: the task asks for it, and it is the usual name for the one namespace-wide `Sidecar`.

`sidecar-third` is not in the list, and that is the whole mechanism. The `Sidecar` resource has no "deny" field: a host that is not listed is simply not sent to the proxy.

---

## Step 3: Confirm The Configuration Shrank

Give `istiod` a few seconds to push the change, then measure again:

```sh
sleep 3
istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -E 'sidecar-other|sidecar-third|local-backend'
```

```text
      16
httpbin.sidecar-other.svc.cluster.local   8000   -   outbound   EDS
local-backend.sidecar-demo.svc.cluster.local   8000   -   outbound   EDS
```

The list went from 34 lines to 16. `sidecar-third` is gone, and the two hosts you kept are still there. No pod restarted: `istiod` sent the change over xDS to the running proxy.

The listener list shows the same change from another angle:

```sh
istioctl proxy-config listener deploy/tester -n sidecar-demo | grep 8000
```

Port `8000` is still there, because two hosts in the list use it. If you also removed `sidecar-other` and ran this again, the line would disappear: `istiod` builds clusters and listeners from the same list of hosts.

---

## Step 4: Verify Reachability Both Ways

The `Sidecar` changes what `tester` can reach, so prove both sides:

```sh
for url in http://local-backend:8000/get \
           http://httpbin.sidecar-other:8000/get \
           http://httpbin.sidecar-third:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n sidecar-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
```

```text
http://local-backend:8000/get -> 200
http://httpbin.sidecar-other:8000/get -> 200
http://httpbin.sidecar-third:8000/get -> 000
```

`000` is how `curl` reports that it never got an HTTP response. You may see `502` instead. Either way the request fails, and the cause is the missing cluster you just confirmed, not DNS and not a `NetworkPolicy`.

Check that the target is still healthy. This is what tells a `Sidecar` apart from deleting the target:

```sh
kubectl -n sidecar-third get deploy,svc
```

```text
deployment.apps/httpbin   1/1   Running
service/httpbin           ClusterIP   8000/TCP
```

The workload runs normally. The `tester` proxy simply has no destination for it.

---

## Common Mistakes

- **Leaving out `istio-system/*`.** Requests inside the namespace keep working, so the mistake survives a quick test. Telemetry and control plane connections do not.
- **Adding a `workloadSelector`.** The task asks for the whole namespace. With a selector, the `local-backend` proxy keeps the full registry.
- **Using `*/*`.** That is the default written down. Nothing gets smaller.
- **Creating a second `Sidecar`.** Two namespace-wide `Sidecar` objects do not merge; the result is not defined. Keep exactly one.
- **Deleting `sidecar-third` or scaling it to zero.** The grader checks that it still runs. The `Sidecar` must stop the traffic.
- **Patching `hosts` and expecting it to add entries.** A merge patch replaces the whole list. Write every host you want to keep.
- **Testing straight after applying.** The push takes a moment. If the cluster list has not changed, wait a few seconds before you decide the object is wrong.
