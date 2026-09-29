# Question

Solve this question on: `terminal`

Istio 1.30.5 is installed. Two namespaces hold workloads:

* `mesh-demo` — `api` (an nginx Deployment behind a Service on port 80) and `reports` (a client pod)
* `legacy-app` — `billing` (an nginx Deployment behind a Service on port 80)

Every pod is `Running`, every Service has endpoints, and every request between them succeeds. Nothing in `kubectl get` looks wrong.

Two of these workloads are **not in the mesh**. Istio can see neither their traffic nor apply any policy to them, and no error anywhere says so.

Find them and bring them into the mesh, so that:

1.  **Every pod in `mesh-demo` and `legacy-app` runs the `istio-proxy` sidecar.**
2.  `legacy-app` is configured so that pods created in it are injected from now on, not just the ones running today.
3.  No workload in either namespace opts out of injection.
4.  All four workloads appear in `istioctl proxy-status`.
5.  Leave the images, replica counts, Services and application configuration unchanged. Do not delete and recreate the Deployments with different specs — the workloads must survive, not be replaced by new ones.

Two things worth knowing before you start:

* Labelling a namespace does **not** change pods that already exist. Injection happens when a pod is created.
* On Kubernetes 1.28 and later the proxy is a **native sidecar**: it appears under a pod's `initContainers` with `restartPolicy: Always`, not under `containers`. It still counts toward the `READY` column, so an injected pod with one application container reads `2/2`.

The grader inspects the pods themselves and asks the control plane what it can see, so the workloads have to genuinely be meshed — not merely relabelled.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — the namespace label, the pod annotation, and when injection happens
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
