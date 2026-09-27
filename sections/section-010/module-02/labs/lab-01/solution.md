# Solution Walkthrough

One object, four lines of `hosts` — but the grader checks the proxy's own configuration and sends live traffic, so the measurement matters as much as the YAML.

---

## Step 1: Measure the Unscoped Baseline

You cannot show a reduction without a number to compare against. Take it first.

```sh
istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -E 'sidecar-other|sidecar-third'
```

```text
      34
httpbin.sidecar-other.svc.cluster.local   8000   -   outbound   EDS
httpbin.sidecar-third.svc.cluster.local   8000   -   outbound   EDS
```

The `tester` proxy carries clusters for both other namespaces, although it calls neither by default. That is the mesh default from Part 1: every proxy gets the whole registry.

Confirm all three destinations are currently reachable:

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

Nothing authorised any of these. They work because the configuration is there.

---

## Step 2: Write the Sidecar

Three entries, and each one is there for a reason:

```sh
kubectl apply -f - <<'EOF'
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
EOF
```

```text
sidecar.networking.istio.io/default created
```

- **No `workloadSelector`.** The task says every workload in the namespace, and omitting the selector is how you say that. Adding one that matches `app: tester` would leave `local-backend`'s proxy unscoped and the grader rejects it.
- **`./*`** — the proxy's own namespace, which keeps `local-backend` reachable.
- **`istio-system/*`** — the control plane and telemetry destinations. Leaving it out produces a partial, diffuse failure that never points back at this object.
- **`sidecar-other/*`** — the one other namespace you were told to keep.

`sidecar-third` is absent, and absence is the whole mechanism. There is no "deny" field.

Name it `default`: the task requires that name, and it is the convention for the one namespace-wide resource.

---

## Step 3: Confirm the Configuration Shrank

Give the push a couple of seconds, then re-measure:

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

From 34 rows to 16, with `sidecar-third` gone and the two you kept still present. No pod restarted — the change arrived over xDS on the running proxy.

The listener dump tells the same story from the other side:

```sh
istioctl proxy-config listener deploy/tester -n sidecar-demo | grep 8000
```

Port 8000 is still there, because two permitted hosts use it. Scope `sidecar-other` away as well and re-run this, and the row disappears entirely — clusters and listeners are built from the same model.

---

## Step 4: Verify Reachability Both Ways

Scoping is a reachability change, so prove both halves:

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

`000` is curl reporting that it never got an HTTP response; you may see `502` instead depending on the mesh's `outboundTrafficPolicy`. Either way the call fails, and the cause is the missing cluster you just confirmed — not DNS, not a NetworkPolicy.

Check that the target is still healthy, which is what distinguishes scoping from deleting:

```sh
kubectl -n sidecar-third get deploy,svc
```

```text
deployment.apps/httpbin   1/1   Running
service/httpbin           ClusterIP   8000/TCP
```

The workload is fine. The caller simply has no route to it.

---

## Common Mistakes

- **Omitting `istio-system/*`.** Application traffic inside the namespace keeps working, so the mistake survives a casual test. Telemetry and control-plane paths do not.
- **Adding a `workloadSelector`.** The task asks for namespace-wide. With a selector, `local-backend`'s proxy keeps the full registry and the reduction is not what was asked for.
- **Using `*/*`.** That is the default written down. Nothing is narrowed.
- **Creating a second `Sidecar`.** Two namespace-wide resources is undefined behaviour, not a merge. Keep exactly one.
- **Deleting `sidecar-third` or scaling it to zero.** The grader checks it is still running. The traffic must be stopped by scoping.
- **Patching `hosts` expecting an append.** A merge patch replaces the list — restate every host you want to keep.
- **Testing immediately after applying.** The push takes a moment. If the cluster list has not moved, wait a few seconds before assuming the object is wrong.
