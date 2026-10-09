# What Sidecar Injection Adds To A Pod

Almost everything you do with Istio is configuration for a proxy. Before that configuration makes sense, you need to know the proxy itself: where it runs, how it gets into a pod, and what it is made of. This part answers those three questions.

You write no configuration here. Everything in this part exists as soon as a namespace is switched on for Istio.

## The problem a service mesh solves

A service that calls other services has to handle jobs that have nothing to do with its own purpose. It must retry failed requests, stop waiting after a timeout, encrypt traffic, pick the right version of the other service, and report what happened. If each application does these jobs itself, every team builds them again in every language and framework. Every rule change then needs a new release of the application.

A **service mesh** moves these jobs out of the application and into a proxy that runs next to it. A proxy is a program that accepts a connection, reads the request and opens its own connection to the destination. Istio adds such a proxy to every pod as an extra container, called the **sidecar proxy**. Istio's control plane, **`istiod`**, turns the objects you write into proxy configuration and sends it to every sidecar proxy.

This has one result that you should remember whenever something behaves strangely: **your application no longer talks to the network directly.** Two sidecar proxies sit between any two services, one in each pod. The behaviour you see is the behaviour of those proxies.

## How injection adds the proxy

So how does the sidecar proxy get into a pod? One label on the namespace switches it on:

```yaml
metadata:
  name: starfleet
  labels:
    istio-injection: enabled
```

This is only a piece of the `starfleet` namespace object, shown to point out the label. You do not apply it: the `starfleet` namespace in your playground already has it.

With this label in place, Istio checks every new pod in the namespace and changes the pod before it starts. Kubernetes calls this kind of check a **mutating admission webhook**: the Kubernetes API server sends each new pod to `istiod`, and `istiod` sends back a changed pod spec with the proxy added. This step is called **sidecar injection**.

The webhook does not change your Deployment. It only changes the pods that the Deployment creates. That is why a namespace that gets the label *after* its pods started needs a `kubectl rollout restart`: the running pods were created before the label existed, and they keep running without a proxy.

Injection adds two containers to the pod spec:

```text
 initContainers:
   istio-init      runs once, writes network rules inside the pod, and exits.
   istio-proxy     restartPolicy: Always: a NATIVE SIDECAR. Listed with the
                   init containers, but it starts before your app and keeps
                   running for the pod's whole life.

 containers:
   <your app>      unchanged
```

The second line surprises many people. An **init container** is a container that Kubernetes runs to completion before the application containers start. On Kubernetes 1.28 and later, an init container with **`restartPolicy: Always`** is a **native sidecar**: Kubernetes starts it in order, like an init container, but does not wait for it to finish. Istio uses this feature, so `istio-proxy` sits in the init container list and still runs the whole time.

Two things follow from this. The proxy is up **before** your application sends its first request. And Kubernetes counts a native sidecar in the `READY` column, so a pod with one application container shows `2/2`.

The `istio-proxy` container runs two programs. **Envoy** is the proxy that handles the requests. **istio-agent** is a small helper that fetches configuration and certificates for Envoy from `istiod`. When this course says "the sidecar proxy", it means Envoy.

## Compare an injected pod with an uninjected pod

The theory says one label makes the difference. Your playground lets you check this with two namespaces. `starfleet` has injection switched on. `outpost` has injection switched off on purpose: its one pod, `drifter`, runs without a sidecar proxy.

<!-- astrona:playground:renew -->

List the pods in both namespaces:

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

Every pod in `starfleet` shows `2/2`: the application container plus the sidecar proxy. The `drifter` pod shows `1/1`. The `shuttle` and `drifter` pods run the same client image. The only difference is the label on their namespace.

> [!TIP]
> When Istio "does nothing" to a workload, check the `READY` column first. `1/1` where you expected `2/2` means the pod has no sidecar proxy, and no Istio rule can reach it.

The `READY` column only counts containers. To see their names, ask the `shuttle` pod for its init containers and its application containers:

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

Both injected containers are init containers, and `restartPolicy` tells them apart. `istio-init` has no restart policy, so it runs once and exits. `istio-proxy` has `Always`, which makes it a native sidecar: Kubernetes starts it before the `shuttle` container and does not wait for it to finish. If the proxy started after the application, the first requests of the application would not pass through the mesh.

You now know what injection adds to a pod: the `istio-init` container that sets up network rules, and the `istio-proxy` native sidecar that runs Envoy. You can also tell an injected pod from an uninjected one by its `READY` column and its init containers. One question is still open: the application never connects to the proxy on purpose, so how do its requests end up there?

## Common pitfalls

> [!WARNING]
> - **Labelling a namespace and expecting running pods to change.** Injection happens when a pod is created. Label the namespace first, then run `kubectl rollout restart deployment -n <namespace>`.
> - **Reading `2/2` as "healthy".** It only means the proxy container exists. A proxy with no useful configuration still shows `2/2`.
> - **Looking for `istio-proxy` under `containers`.** On Kubernetes 1.28 and later it is a native sidecar, listed under `initContainers` with `restartPolicy: Always`.
