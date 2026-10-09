# Solution Walkthrough

Two workloads run outside the mesh for two *different* reasons, and neither reason produces an error. The whole lab practises one habit: what `kubectl get` shows you and what the mesh actually sees are two different facts.

---

## Step 1: Look At The READY Column

`kubectl get pods` looks healthy everywhere. So look at the column that shows whether a pod has its sidecar proxy, not the column that shows whether it runs:

```sh
kubectl -n mesh-demo get pods
kubectl -n legacy-app get pods
```

```text
NAME                       READY   STATUS    RESTARTS   AGE
api-6c9f7d8b84-2xq4r       2/2     Running   0          3m
reports-5f8c6d7b9c-nk82p   1/1     Running   0          3m
NAME                       READY   STATUS    RESTARTS   AGE
billing-7d5b8c6f94-tm9vk   1/1     Running   0          3m
```

`api` shows `2/2`: the application container plus the `istio-proxy` sidecar. `reports` and `billing` show `1/1`. They are just as healthy, but their pods have no sidecar proxy.

The control plane, `istiod`, agrees. Ask it which proxies are connected:

```sh
istioctl proxy-status
```

Only `api` appears. A workload that is missing from this list has no proxy connected to `istiod`.

---

## Step 2: Find Out Why: Two Different Causes

Check the namespace labels first. They explain one of the two workloads, but not the other:

```sh
kubectl get namespace mesh-demo legacy-app --show-labels
```

```text
NAME         STATUS   AGE   LABELS
mesh-demo    Active   3m    istio-injection=enabled,kubernetes.io/metadata.name=mesh-demo
legacy-app   Active   3m    kubernetes.io/metadata.name=legacy-app
```

`legacy-app` has no `istio-injection` label, which explains `billing`. But `reports` runs in `mesh-demo`, which *has* the label, and it still shows `1/1`. So something on the workload itself turns injection off. Read the annotations on its pod template:

```sh
kubectl -n mesh-demo get deployment reports \
  -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

```text
{"sidecar.istio.io/inject":"false"}
```

The pod template opts out with the `sidecar.istio.io/inject: "false"` annotation. The namespace label turns injection on, the pod annotation turns it off, and the pod annotation wins.

---

## Step 3: Label The Namespace, Then Restart The Pods

Add the injection label to `legacy-app`:

```sh
kubectl label namespace legacy-app istio-injection=enabled
```

On its own, this changes nothing you can see, and many people miss this. Istio adds the sidecar in a mutating admission webhook **when Kubernetes creates a pod**. The running pod was created before the label existed, so it stays as it is:

```sh
kubectl -n legacy-app get pods
```

```text
billing-7d5b8c6f94-tm9vk   1/1     Running   0          4m
```

The output is shortened: the header line is left out. The pod still shows `1/1`, because the label only applies to pods created from now on. Restart the Deployment so that Kubernetes creates new pods:

```sh
kubectl -n legacy-app rollout restart deployment
kubectl -n legacy-app rollout status deployment/billing
```

---

## Step 4: Remove The Opt-Out

Set the annotation on the `reports` pod template to `true` (removing it works too):

```sh
kubectl -n mesh-demo patch deployment reports --type merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true"}}}}}'
```

A change to the pod template starts a new rollout by itself, so you do not need a separate restart.

---

## Step 5: Check The Result In Two Ways

Check the pods and the list of connected proxies:

```sh
kubectl -n mesh-demo get pods
kubectl -n legacy-app get pods
istioctl proxy-status
```

```text
api-6c9f7d8b84-2xq4r       2/2   Running
reports-6b4d9c8f75-p2w8r   2/2   Running
billing-8c6f4d5b93-x7k2m   2/2   Running
```

The output is shortened: it shows only the pod lines of the two `kubectl` commands, without headers and extra columns. All three pods show `2/2`, and all three now appear in `istioctl proxy-status`. These are the two facts the grader checks, and you want both.

To see *why* a pod with one application container shows `2/2`, look at where the proxy is listed. A `-l` label selector returns a list of pods, so the path starts at `.items[0]`, the first pod in that list:

```sh
kubectl -n legacy-app get pod -l app=billing \
  -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{" restartPolicy="}{.restartPolicy}{"\n"}{end}'
```

```text
istio-init restartPolicy=
istio-proxy restartPolicy=Always
```

Both injected containers are init containers. `istio-init` runs once and exits. `istio-proxy` has `restartPolicy: Always`, which makes it a **native sidecar**: Kubernetes starts it before the application and does not wait for it to finish. Kubernetes counts native sidecars in the `READY` column, which gives the second number in `2/2`.

---

## Step 6: Submit

```sh
astrona submit
```

---

## Common Mistakes

* **Labelling the namespace and stopping there.** The existing pods were created before the label. Without a `rollout restart` nothing changes, and `kubectl get ns --show-labels` still shows a label that has no effect yet.
* **Deleting and recreating the Deployments.** The task is to bring these workloads into the mesh, not to replace them.
* **Looking only at the namespace.** One of the two causes is on the workload, and a namespace label cannot override an opt-out annotation on the pod template.
* **Looking for `istio-proxy` under `containers`.** On Kubernetes 1.28 and later it is in `initContainers` with `restartPolicy: Always`.
* **Trusting `Running`.** Both workloads run as healthy pods. `1/1` where you expected `2/2` is the only sign of the problem.
