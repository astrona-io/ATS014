# Meet The Communications Officer

Astronaut, everything in this course is a way of giving orders to a proxy. Before those orders make sense, you need to meet the proxy itself: where it sits, how it got on board, and what it is made of. That is this part.

Nothing here is configuration you write. It is what exists the moment a planet (a namespace) is switched on for Istio.

## The problem a mesh solves

A service that calls other services has to deal with jobs that have nothing to do with what the service is for: retries, timeouts, encryption, which version of another service to call, what to do when it is slow, and how to report what happened. Build those jobs into the application, and you build them once per language, per framework and per team, and you redeploy the application every time a rule changes.

A **service mesh** moves those jobs out of the application and into a helper that sits beside it. Picture the fleet's shared signal network. Istio puts a second container into every pod (every spaceship): a proxy, the ship's **communications officer**. A control plane, **mission control** (`istiod`), gives every communications officer their orders from one set of objects you write.

Remember the trade whenever something behaves strangely later: **your application no longer talks to the network directly.** Two communications officers sit between any two services, one on each ship, and the behaviour you see is theirs.

## What injection adds to a pod

One label on the namespace switches it on:

```yaml
metadata:
  name: starfleet
  labels:
    istio-injection: enabled
```

This is only a piece of the namespace object, to show the label. You do not apply it: your playground's `starfleet` planet already has it.

With that label in place, Istio checks every new pod on that planet and rewrites the pod before it starts. The Kubernetes name for that check is a **mutating admission webhook**. Think of the launch pad crew putting a communications officer on board every ship that launches from this planet.

Your Deployment is not changed. Only the pods it creates are. That is why a namespace labelled *after* its pods started needs a `kubectl rollout restart`: the ships already flying launched before the rule existed, and they keep flying without a communications officer.

Two containers are added:

```text
 initContainers:
   istio-init      runs once, writes network rules inside the pod, and exits.
   istio-proxy     restartPolicy: Always: a NATIVE SIDECAR. Listed with the
                   init containers, but it starts before your app and keeps
                   running for the pod's whole life.

 containers:
   <your app>      unchanged
```

The second line surprises people. On Kubernetes 1.28 and later, an init container with **`restartPolicy: Always`** is a *native sidecar*: Kubernetes starts it in order, like an init container, but never waits for it to finish. Istio uses this, so `istio-proxy` sits in the init list and still runs the whole time.

Two things follow. The proxy is up **before** your application sends its first signal. And a native sidecar still counts in the `READY` column, so a pod with one application container shows `2/2`.

`istio-proxy` holds two programs. **Envoy** is the proxy that moves the signals: the communications officer at the radio. **istio-agent** is a small helper that fetches orders and certificates for Envoy from mission control. When this course says "the sidecar", it means Envoy.

<!-- astrona:playground:renew -->

### See the difference in one column

Your playground has two planets. `starfleet` has injection switched on. `outpost` does not: its one ship, the `drifter`, flies without a communications officer, on purpose. List the ships on both:

```sh
kubectl -n starfleet get pods
kubectl -n outpost get pods
```

You should see:

```text
NAME                         READY   STATUS    RESTARTS   AGE
bridge-v1-bc4dc4fcc-vqnrp    2/2     Running   0          70s
cargo-v1-6f787f8bd5-hv62g    2/2     Running   0          70s
navcom-v1-7467bbc689-lg8xb   2/2     Running   0          70s
probe-v1-7888d6c6d5-hvrtl    2/2     Running   0          70s
probe-v2-58767cc46-x9qq9     2/2     Running   0          70s
scout-v1-85bf65868-s745c     2/2     Running   0          70s
scout-v2-866c98b568-tjdv5    2/2     Running   0          70s
scout-v3-668c6dfc68-hvfxm    2/2     Running   0          70s
shuttle-7b5db664c-zsftm      2/2     Running   0          70s
NAME                       READY   STATUS    RESTARTS   AGE
drifter-57fdbc6c95-2gsjk   1/1     Running   0          70s
```

Every ship on `starfleet` shows `2/2`: the app plus its communications officer. The drifter shows `1/1`. The `shuttle` and the `drifter` run the same image; the only difference is one label on the planet.

> [!TIP]
> When Istio "is not doing anything" to a workload, check the `READY` column first. `1/1` where you expected `2/2` means there is no communications officer on board, and no Istio rule can reach that ship.

### Name the containers

The `READY` column only counts containers. Ask the shuttle's pod which ones it runs:

```sh
kubectl -n starfleet get pod -l app=shuttle \
  -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{" restartPolicy="}{.restartPolicy}{"\n"}{end}{"--- containers ---\n"}{.items[0].spec.containers[*].name}{"\n"}'
```

You should see:

```text
istio-init restartPolicy=
istio-proxy restartPolicy=Always
--- containers ---
shuttle
```

Both injected containers are init containers, and `restartPolicy` tells them apart. `istio-init` has none, so it runs once and exits. `istio-proxy` has `Always`, which makes it a native sidecar: started before `shuttle`, and never waited on. If the proxy started after the app, the app's first signals would escape the mesh.

## Common pitfalls

> [!WARNING]
> - **Labelling a namespace and expecting running pods to change.** Injection happens when a pod is created. Label first, then `kubectl rollout restart deployment -n <namespace>`.
> - **Reading `2/2` as "healthy".** It only means the proxy container exists. A proxy with no useful orders still shows `2/2`.
> - **Looking for `istio-proxy` under `containers`.** On Kubernetes 1.28 and later it is a native sidecar, listed under `initContainers` with `restartPolicy: Always`.

> *Injection puts a communications officer on board every new ship. Everything else in this course is orders for that officer.*
