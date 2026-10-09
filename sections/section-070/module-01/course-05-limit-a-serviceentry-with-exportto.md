# Limit A ServiceEntry With exportTo

A `ServiceEntry` adds a host outside the mesh to the service registry, the list of hosts that `istiod`, Istio's control plane, sends to every sidecar proxy. A sidecar proxy (Envoy) is the proxy container next to each application container; every request the pod sends passes through it. By default a `ServiceEntry` is exported to every namespace, so one team's entry opens the host for the whole mesh. The **`exportTo`** field lets the owner of the entry limit which namespaces may use it.

This setting can also hide a correct entry from a caller. The symptom is the same as a missing entry: `000` in `curl`, and `BlackHoleCluster` in the access log, the name the sidecar proxy writes when it drops a request to a host that is not in its configuration. This part shows that case, and then the clean way to give one namespace exactly one external host.

The commands below run under `REGISTRY_ONLY`, the outbound traffic policy that makes the sidecar proxy refuse every host outside the service registry. A `Sidecar` resource sets it for one namespace. A `Sidecar` also limits which hosts the sidecar proxies of that namespace get configuration for, through its `egress.hosts` list.

## A `Sidecar` that takes in the entry

Start from a `Sidecar` that already lets the `starfleet` pods see `httpbin.org` from the namespace `default`. It refuses every host outside the registry, and its `egress.hosts` list takes in the `starfleet` namespace, `istio-system`, and the one host `default/httpbin.org`, in the form `<namespace>/<host>`. If your terminal does not have the `call_external` helper yet, paste it now. It sends one request from the `shuttle` pod and prints the status code, the time and the exit code of `curl`:

<!-- astrona:playground:renew -->

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

Then make sure the `Sidecar` is in place. Save this as `sidecar-registry-only-with-default.yaml`:

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

With this `Sidecar`, the caller's side allows the entry. Any refusal from now on comes from the entry itself.

## An `exportTo` that keeps the entry in its namespace

Now look at the setting that belongs to the owner of the entry. Another team owns an entry for `httpbin.org` in the namespace `default`, and it decides to keep the entry private. Save this as `serviceentry-httpbin-org-in-default-private.yaml`:

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

The request is refused again, while the `Sidecar` still lists `default/httpbin.org`. `exportTo: ["."]` keeps the entry inside `default`, and `starfleet` is not `default`. Again `istioctl analyze` is quiet, because each object is valid on its own. Only the `shuttle` pod's sidecar proxy shows the real state: `istioctl proxy-config cluster` lists the clusters, that is the destinations, that the proxy knows, and `httpbin.org` is not one of them.

## The clean fix: put the entry in the caller's namespace

Both settings allow the entry by themselves when it lives in the same namespace as the pods that use it. `./*` in the `Sidecar` takes it in, and `exportTo: ["."]` keeps it from reaching any other namespace. That is the safest default for a namespace with `REGISTRY_ONLY`.

Remove the entry from `default`, and put the `Sidecar` back to the form without the `default/httpbin.org` line:

```sh
kubectl delete -f serviceentry-httpbin-org-in-default-private.yaml
kubectl apply -f sidecar-registry-only.yaml
```

If you no longer have `sidecar-registry-only.yaml`, it is the `Sidecar` named `default` in `starfleet` with `outboundTrafficPolicy.mode: REGISTRY_ONLY` and `egress.hosts` set to `./*` and `istio-system/*`, the same as the `Sidecar` above without the `default/httpbin.org` line.

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
> - **Forgetting that `exportTo` belongs to the owner.** A caller's `Sidecar` cannot take in an entry that its owner did not export to the caller's namespace.
> - **Trusting `istioctl analyze` here.** An entry hidden by `exportTo` is valid configuration, so `analyze` stays quiet. `istioctl proxy-config cluster` on the calling pod shows whether it can see the host.
> - **Assuming a `ServiceEntry` is private to its namespace.** Without `exportTo`, it is exported to every namespace, so one namespace's allow-list becomes everyone's.

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
