# Question

Solve this question on: `terminal`

Two workloads in this cluster are running outside the mesh, and nobody has noticed. Istio 1.30.5 is installed. Two namespaces hold workloads:

* `mesh-demo`: `api` (an nginx Deployment behind a Service on port 80) and `reports` (a client pod)
* `legacy-app`: `billing` (an nginx Deployment behind a Service on port 80)

Every pod is `Running`, every Service has endpoints, and every request between them succeeds. Nothing in `kubectl get` looks wrong.

Two of these workloads are **not in the mesh**: their pods have no sidecar proxy. The sidecar proxy is the `istio-proxy` container that Istio adds to a pod; all traffic in and out of the pod passes through it. Without it, Istio cannot see the traffic of the workload or apply any rule to it, and no error says so.

Find the two workloads and bring them into the mesh, so that:

1.  **Every pod in `mesh-demo` and `legacy-app` runs the `istio-proxy` sidecar.**
2.  `legacy-app` is configured so that pods created in it get the sidecar from now on, not just the pods running today.
3.  No workload in either namespace opts out of sidecar injection.
4.  All three workloads (`api`, `reports` and `billing`) appear in `istioctl proxy-status`.
5.  The images, replica counts, Services and application configuration stay unchanged. Do not delete and recreate the Deployments: the grader checks that the same workloads are still there.

Two facts to know before you start:

* Labelling a namespace does **not** change pods that already exist. Sidecar injection happens when Kubernetes creates a pod.
* On Kubernetes 1.28 and later the proxy is a **native sidecar**: it appears under a pod's `initContainers` with `restartPolicy: Always`, not under `containers`. Kubernetes still counts it in the `READY` column, so an injected pod with one application container shows `2/2`.

The grader checks the pods themselves and asks the control plane, `istiod`, which proxies it can see. The workloads must really run a connected proxy; a label alone does not pass.
