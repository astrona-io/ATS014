# Solution Walkthrough

Two workloads are outside the mesh for two *different* reasons, and neither reason produces an error. The whole lab is an exercise in the module's standing habit: what `kubectl get` shows you and what the mesh actually sees are different facts.

---

## Step 1: Ask The Right Question

`kubectl get pods` looks healthy everywhere, so look at the column that means "injected" rather than the one that means "running":

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

`api` is `2/2`. The other two are `1/1`. Same images, same health, no proxy.

The control plane agrees:

```sh
istioctl proxy-status
```

Only `api` appears. A workload missing from that list is not connected to the control plane at all.

---

## Step 2: Find Out *Why* — They Are Not The Same Fault

Check the namespace label first, because it explains one of them and not the other:

```sh
kubectl get namespace mesh-demo legacy-app --show-labels
```

```text
NAME         STATUS   AGE   LABELS
mesh-demo    Active   3m    istio-injection=enabled,kubernetes.io/metadata.name=mesh-demo
legacy-app   Active   3m    kubernetes.io/metadata.name=legacy-app
```

`legacy-app` was never labelled — that is `billing` explained. But `reports` lives in `mesh-demo`, which *is* labelled, and it still came up `1/1`. Something on the workload itself is refusing:

```sh
kubectl -n mesh-demo get deployment reports \
  -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

```text
{"sidecar.istio.io/inject":"false"}
```

An explicit opt-out on the pod template. The namespace label says yes, the pod annotation says no, and the pod wins.

---

## Step 3: Fix The Namespace — And Remember The Restart

```sh
kubectl label namespace legacy-app istio-injection=enabled
```

That alone changes nothing you can see, and this is the part people miss. Injection happens in an admission webhook **when a pod is created**. Every pod already running was admitted before the rule applied, so it stays exactly as it is:

```sh
kubectl -n legacy-app get pods
```

```text
billing-7d5b8c6f94-tm9vk   1/1     Running   0          4m
```

Still `1/1`. The label governs the future. Recreate the pods to collect it:

```sh
kubectl -n legacy-app rollout restart deployment
kubectl -n legacy-app rollout status deployment/billing
```

---

## Step 4: Fix The Opt-Out

Remove the refusal, or set it to `true`:

```sh
kubectl -n mesh-demo patch deployment reports --type merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true"}}}}}'
```

Patching the pod template changes the template hash, so this triggers its own rollout — no separate restart needed.

---

## Step 5: Confirm, Two Ways

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

All `2/2`, and all three now appear in `proxy-status`. Those are the two different facts, and you want both.

If you want to see *why* it is `2/2` with only one application container, look at where the proxy actually is:

```sh
kubectl -n legacy-app get pod -l app=billing \
  -o jsonpath='{range .spec.initContainers[*]}{.name}{" restartPolicy="}{.restartPolicy}{"\n"}{end}'
```

```text
istio-init restartPolicy=
istio-proxy restartPolicy=Always
```

Both injected pieces are init containers. `istio-init` runs once and exits; `istio-proxy` has `restartPolicy: Always`, which makes it a **native sidecar** — started in order, before the app, and never waited on. Native sidecars count toward `READY`, which is where the second number comes from.

---

## Step 6: Submit

```sh
astrona submit
```

---

## Common Mistakes

* **Labelling the namespace and stopping there.** Existing pods were admitted under the old rule. Without a `rollout restart` nothing changes, and `kubectl get ns --show-labels` will happily show you a label that is doing nothing yet.
* **Deleting and recreating the Deployments.** It works, and the grader rejects it — the task is to bring these workloads into the mesh, not to replace them.
* **Looking only at the namespace.** One of the two faults is on the workload, and a namespace label cannot override a pod-template opt-out.
* **Looking for `istio-proxy` under `containers`.** On Kubernetes 1.28+ it is in `initContainers` with `restartPolicy: Always`.
* **Trusting `Running` and `1/1`.** Both faults are perfectly healthy pods. `1/1` where you expected `2/2` is the entire signal.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — the namespace label, the pod annotation, and when injection happens
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
