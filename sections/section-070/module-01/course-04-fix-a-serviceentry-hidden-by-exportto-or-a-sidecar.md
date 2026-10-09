# Fix A ServiceEntry Hidden By exportTo Or A Sidecar

A `ServiceEntry` adds a host outside the mesh to the service registry, the list of hosts that `istiod`, Istio's control plane, sends to every sidecar proxy. A `ServiceEntry` can be perfectly correct and still not work. The symptom is exactly the same as a missing one: `000` or `502` in `curl`, and `BlackHoleCluster` or `block_all` in the access log. This is the diagnosis worth taking out of the module.

The cause is almost never in the `ServiceEntry` itself. It is in **which sidecar proxies may see it**. Two settings decide that, and one of them belongs to another object.

The commands below need the `REGISTRY_ONLY` `Sidecar` resource named `default` in the `starfleet` namespace applied in your playground. It refuses every host outside the registry, and its `egress.hosts` list is `./*` and `istio-system/*`.

## Two settings between a ServiceEntry and a caller

For a pod's sidecar proxy to use a `ServiceEntry`, two settings must allow it:

1. **The entry's `exportTo`.** The owner of the `ServiceEntry` decides which namespaces may use it. The default is every namespace.
2. **The caller's `Sidecar` resource.** A `Sidecar` resource limits which hosts the sidecar proxies of one namespace get configuration for. Its `egress.hosts` list decides which namespaces the caller takes configuration from. `./*` only means "my own namespace".

So a mesh-wide `ServiceEntry` in the namespace `default` is still invisible to a pod whose `Sidecar` lists only `./*` and `istio-system/*`. And a `ServiceEntry` that the `Sidecar` does list is still invisible if its own `exportTo` leaves out the caller's namespace. When a request is refused, check in this order:

```mermaid
flowchart TB
    F["BlackHoleCluster"] --> A{"ServiceEntry"}
    A -->|"missing"| A1["create it"]
    A -->|"exists"| B{"exportTo"}
    B -->|"leaves out caller namespace"| B1["widen exportTo or move the entry"]
    B -->|"includes caller namespace"| C{"Sidecar egress.hosts"}
    C -->|"leaves out entry namespace"| C1["add it or move the entry"]
    C -->|"includes entry namespace"| D["check ports and protocol"]
```

The diagram shows the three checks, from the existence of the entry to the caller's `Sidecar`, before you look at ports and protocol.

The rule to remember: **when a `ServiceEntry` works from one namespace and not from another, look for a `Sidecar` before you read the `ServiceEntry` again.** Your best tool is the caller's own sidecar proxy. If the host is not in `istioctl proxy-config cluster` for the calling pod, that pod cannot see the entry, however correct the entry is.

## Start from a clean namespace

Remove every `ServiceEntry`, `VirtualService` and `DestinationRule` from `starfleet`, so the earlier objects do not hide the effect. The `Sidecar` resource stays.

<!-- astrona:playground:renew -->

```sh
kubectl delete serviceentry,virtualservice,destinationrule --all -n starfleet
```

```text
serviceentry.networking.istio.io "httpbin-org" deleted from starfleet namespace
virtualservice.networking.istio.io "httpbin-org" deleted from starfleet namespace
destinationrule.networking.istio.io "httpbin-org" deleted from starfleet namespace
```

If your terminal does not have the `call_external` helper yet, paste it now. It sends one request from the `shuttle` pod and prints the status code, the time and the exit code of `curl`:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

## A `Sidecar` that leaves the entry out

Start with the setting that belongs to the caller. Another team adds `httpbin.org` to the registry in its own namespace, and the `shuttle` pod tries to use it. Put a correct `ServiceEntry` in the namespace `default`. It has no `exportTo`, so it is exported to every namespace. Save this as `serviceentry-httpbin-org-in-default.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-org
  namespace: default
spec:
  hosts:
  - httpbin.org
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-httpbin-org-in-default.yaml
```

Then call the host, list the entries, look in the `shuttle` pod's sidecar proxy, and run `istioctl analyze`:

```sh
call_external https://httpbin.org/get
kubectl get serviceentry -A
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org || echo "(no match)"
istioctl analyze -n starfleet
```

You should see:

```text
000 0.029325s
command terminated with exit code 35
  exit=35
NAMESPACE   NAME          HOSTS             LOCATION        RESOLUTION   AGE
default     httpbin-org   ["httpbin.org"]   MESH_EXTERNAL   DNS          5s
(no match)
✔ No validation issues found when analyzing namespace: starfleet.
```

The request is still refused. The entry exists and is exported everywhere, but the `shuttle` pod's sidecar proxy has no cluster for `httpbin.org`. `istioctl analyze` finds nothing wrong, because each object is valid on its own. The `starfleet` `Sidecar` takes configuration only from `starfleet` and `istio-system`, so the entry in `default` never reaches the `shuttle` pod.

To fix it from the caller's side, add exactly this one host from `default` to the `Sidecar`. The form is `<namespace>/<host>`. Save this as `sidecar-registry-only-with-default.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: starfleet
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
    - "default/httpbin.org"
```

Apply it:

```sh
kubectl apply -f sidecar-registry-only-with-default.yaml
```

Then check the result:

```sh
call_external https://httpbin.org/get
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org || echo "(no match)"
```

You should see:

```text
200 0.490421s
  exit=0
httpbin.org                               443       -          outbound      STRICT_DNS
```

The same `ServiceEntry`, untouched, now works. Only the `Sidecar` changed. `default/httpbin.org` takes in one host from `default`, while `default/*` would take in everything there.

## An `exportTo` that keeps the entry in its namespace

Now look at the other setting, which belongs to the owner of the entry. The owner of the entry in `default` decides to keep it private. Save this as `serviceentry-httpbin-org-in-default-private.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-org
  namespace: default
spec:
  hosts:
  - httpbin.org
  exportTo:
  - "."
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-httpbin-org-in-default-private.yaml
```

Then check the result:

```sh
call_external https://httpbin.org/get
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org || echo "(no match)"
istioctl analyze -n starfleet
```

You should see:

```text
000 0.020038s
command terminated with exit code 35
  exit=35
(no match)
✔ No validation issues found when analyzing namespace: starfleet.
```

The request is refused again, while the `Sidecar` still lists `default/httpbin.org`. `exportTo: ["."]` keeps the entry inside `default`, and `starfleet` is not `default`. Again `istioctl analyze` is quiet. Only the `shuttle` pod's sidecar proxy shows the real state.

## The clean fix: put the entry in the caller's namespace

Both settings allow the entry by themselves when it lives in the same namespace as the pods that use it. `./*` in the `Sidecar` takes it in, and `exportTo: ["."]` keeps it from reaching any other namespace. That is the safest default for a namespace with `REGISTRY_ONLY`.

Remove the entry from `default`, and put the `Sidecar` back to its first form:

```sh
kubectl delete -f serviceentry-httpbin-org-in-default-private.yaml
kubectl apply -f sidecar-registry-only.yaml
```

If you no longer have `sidecar-registry-only.yaml`, it is the `Sidecar` named `default` in `starfleet` with `outboundTrafficPolicy.mode: REGISTRY_ONLY` and `egress.hosts` set to `./*` and `istio-system/*`, the same as above without the `default/httpbin.org` line.

Save this as `serviceentry-httpbin-org-private.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-org
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  exportTo:
  - "."
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-httpbin-org-private.yaml
```

Then call the allowed host and one that is not in the registry:

```sh
call_external https://httpbin.org/get
call_external https://www.google.com
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org || echo "(no match)"
```

You should see:

```text
200 0.509702s
  exit=0
000 0.039927s
command terminated with exit code 35
  exit=35
httpbin.org                               443       -          outbound      STRICT_DNS
```

`httpbin.org` is now open for `starfleet` only. Every other namespace in the mesh, and every other host on the internet, stays closed.

You can now tell a missing `ServiceEntry` from a hidden one, and you know the two settings that hide one: the entry's `exportTo` and the caller's `Sidecar` `egress.hosts`. You also know that `istioctl analyze` does not report this case, and that `istioctl proxy-config cluster` on the calling pod does. The question to ask every time is whether the caller's own sidecar proxy has a cluster for the host.

## Common pitfalls

> [!WARNING]
> - **Reading the `ServiceEntry` again and again.** When it works from one namespace and not another, the cause is usually a `Sidecar`'s `egress.hosts`, or the entry's `exportTo`.
> - **Trusting `istioctl analyze` here.** A hidden entry is valid configuration, so `analyze` stays quiet. `istioctl proxy-config cluster` on the calling pod shows whether it can see the host.
> - **Fixing it with `*/*` in the `Sidecar`.** That takes in every namespace's configuration and removes the limit the `Sidecar` was there to set. Add the one namespace or host you need.
> - **Switching the `Sidecar` back to `ALLOW_ANY`.** The request gets out through `PassthroughCluster`, with no rules. The refusal is gone, and so is the control.
> - **Forgetting that `exportTo` belongs to the owner.** A caller's `Sidecar` cannot take in an entry that its owner did not export to the caller's namespace.

## Your mission: Fix A Hidden ServiceEntry And Its Port Protocol Lab

You can now find a `ServiceEntry` that a caller cannot see, and prove it from the caller's own sidecar proxy. In the lab, a `ServiceEntry` and a `VirtualService` for an external host called `relay` look correct, but every request from the `shuttle` pod is refused, and more than one fault stands in the way.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-070-01-02
astrona start ats-014-playground-070-01
```
