# Solution Walkthrough

This walkthrough follows the task and ends each section with a check. Items 2 and 3 are the two fixes, so they come first. Item 1 is the result of both fixes, so you check it right after them. Items 4 and 5 close the walkthrough.

---

## Start: Find The Two Workloads

The task says that every pod is `Running` and that two workloads run without a sidecar proxy. The sidecar proxy is the `istio-proxy` container that Istio adds to a pod. Look at the `READY` column. A pod with one application container and a sidecar shows `2/2`. Without the sidecar it shows `1/1`:

```sh
kubectl -n mesh-demo get pods
kubectl -n legacy-app get pods
```

```text
NAME                       READY   STATUS    RESTARTS   AGE
api-8776d7b95-llrvc        2/2     Running   0          4s
reports-58b99548b4-tp4xr   1/1     Running   0          4s
NAME                       READY   STATUS    RESTARTS   AGE
billing-764b947dc7-jnc4t   1/1     Running   0          4s
```

`reports` and `billing` show `1/1`, so they have no sidecar. `istiod`, the Istio control plane, agrees. List the proxies that are connected to it:

```sh
istioctl proxy-status
```

```text
NAME                                                 ...
api-8776d7b95-llrvc.mesh-demo                        ...
istio-egressgateway-b7dd4655b-tgkxr.istio-system     ...
istio-ingressgateway-7f54444996-cv5mw.istio-system   ...
```

The output is shortened to the first column. Only `api` appears from the two namespaces. The other lines are the two Istio gateways.

The two workloads have different causes. Check the namespace labels first:

```sh
kubectl get namespace mesh-demo legacy-app --show-labels
```

```text
NAME         STATUS   AGE   LABELS
mesh-demo    Active   4s    istio-injection=enabled,kubernetes.io/metadata.name=mesh-demo
legacy-app   Active   4s    kubernetes.io/metadata.name=legacy-app
```

`legacy-app` has no `istio-injection` label. That explains `billing`. But `mesh-demo` has the label, and `reports` still shows `1/1`. So the workload itself must turn injection off. Read the annotations of its pod template:

```sh
kubectl -n mesh-demo get deployment reports \
  -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

```text
{"sidecar.istio.io/inject":"false"}
```

The annotation `sidecar.istio.io/inject: "false"` on the pod template opts `reports` out. The namespace label turns injection on, and the pod annotation turns it off. The pod annotation wins.

Before you change anything, save the identity of the three Deployments. Item 5 compares against it later:

```sh
kubectl get deploy -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPL:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image,UID:.metadata.uid | grep -E "mesh-demo|legacy-app|NS"
```

```text
NS                   NAME                     REPL   IMAGE                                                         UID
legacy-app           billing                  1      nginx:1.27-alpine                                             08f164b3-edd9-42f2-becb-52f253050d5e
mesh-demo            api                      1      nginx:1.27-alpine                                             917084ee-5185-4017-bc0d-32b08a764d7e
mesh-demo            reports                  1      curlimages/curl                                               9387326f-6134-480e-87bc-993e5e31ec8a
```

---

## Item 2: Make `legacy-app` Inject Sidecars From Now On

> **Task item 2:** `legacy-app` is configured so that pods created in it get the sidecar from now on, not just the pods running today.

Label the namespace:

```sh
kubectl label namespace legacy-app istio-injection=enabled
```

```text
namespace/legacy-app labeled
```

The label does not change the pod that already runs. Istio adds the sidecar in a mutating admission webhook when Kubernetes creates a pod. The `billing` pod was created before the label existed:

```sh
kubectl -n legacy-app get pods
```

```text
NAME                       READY   STATUS    RESTARTS   AGE
billing-764b947dc7-jnc4t   1/1     Running   0          5s
```

It still shows `1/1`. Restart the Deployment, so that Kubernetes creates a new pod. A restart keeps the same Deployment, and item 5 asks for that:

```sh
kubectl -n legacy-app rollout restart deployment
kubectl -n legacy-app rollout status deployment/billing
```

```text
deployment.apps/billing restarted
Waiting for deployment "billing" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "billing" rollout to finish: 1 old replicas are pending termination...
deployment "billing" successfully rolled out
```

Check item 2. The task says "from now on", so prove that a pod created later gets the sidecar. Check the label, then delete the `billing` pod and let the Deployment create a new one:

```sh
kubectl get namespace legacy-app -L istio-injection
kubectl -n legacy-app delete pod -l app=billing
kubectl -n legacy-app rollout status deployment/billing
kubectl -n legacy-app get pods
```

```text
NAME         STATUS   AGE   ISTIO-INJECTION
legacy-app   Active   30s   enabled
pod "billing-795c85b584-26zrl" deleted from legacy-app namespace
NAME                       READY   STATUS    RESTARTS   AGE
billing-795c85b584-jhx8k   2/2     Running   0          2s
```

The new pod shows `2/2` without any extra step. The namespace label does the work for every new pod.

---

## Item 3: Remove The Opt-Out From `reports`

> **Task item 3:** No workload in either namespace opts out of sidecar injection.

Set the annotation on the `reports` pod template to `true`. Removing the annotation also works. A change to the pod template starts a new rollout, so you need no separate restart:

```sh
kubectl -n mesh-demo patch deployment reports --type merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"true"}}}}}'
kubectl -n mesh-demo rollout status deployment/reports
```

```text
deployment.apps/reports patched
Waiting for deployment "reports" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "reports" rollout to finish: 1 old replicas are pending termination...
deployment "reports" successfully rolled out
```

Check item 3. Print the `sidecar.istio.io/inject` annotation of every Deployment in both namespaces:

```sh
for ns in mesh-demo legacy-app; do
  kubectl -n $ns get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" inject="}{.spec.template.metadata.annotations.sidecar\.istio\.io/inject}{"\n"}{end}'
done
```

```text
api inject=
reports inject=true
billing inject=
```

No Deployment has the value `false`. An empty value means the Deployment has no annotation, so the namespace setting applies.

---

## Item 1: Every Pod Runs The Sidecar

> **Task item 1:** **Every pod in `mesh-demo` and `legacy-app` runs the `istio-proxy` sidecar.**

Items 2 and 3 fixed both causes. Now check the pods:

```sh
kubectl -n mesh-demo get pods
kubectl -n legacy-app get pods
```

```text
NAME                       READY   STATUS        RESTARTS   AGE
api-8776d7b95-llrvc        2/2     Running       0          32s
reports-58b99548b4-tp4xr   1/1     Terminating   0          32s
reports-f9b8d7559-58vsn    2/2     Running       0          25s
NAME                       READY   STATUS    RESTARTS   AGE
billing-795c85b584-jhx8k   2/2     Running   0          2s
```

The `reports-58b99548b4-tp4xr` pod is the old pod. It shows `Terminating` and disappears after a short time. All pods that stay show `2/2`.

A pod with one application container shows `2/2`, not `1/1`, because the proxy counts in the `READY` column. Look at where the proxy runs:

```sh
kubectl -n legacy-app get pod -l app=billing \
  -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{" restartPolicy="}{.restartPolicy}{"\n"}{end}'
```

```text
istio-init restartPolicy=
istio-proxy restartPolicy=Always
```

On Kubernetes 1.28 and later the proxy is a native sidecar. It is an init container with `restartPolicy: Always`, so Kubernetes starts it before the application and keeps it running. `istio-init` runs once and exits.

---

## Item 4: The Control Plane Sees All Three Workloads

> **Task item 4:** All three workloads (`api`, `reports` and `billing`) appear in `istioctl proxy-status`.

```sh
istioctl proxy-status | grep -E "NAME|mesh-demo|legacy-app"
```

```text
NAME                                  ...
api-8776d7b95-llrvc.mesh-demo         ...
billing-795c85b584-jhx8k.legacy-app   ...
reports-f9b8d7559-58vsn.mesh-demo     ...
```

The output is shortened to the first column. All three workloads have a proxy that is connected to `istiod`. If one is missing, wait a few seconds and run the command again. A new proxy needs a moment to connect.

---

## Item 5: Nothing Else Changed

> **Task item 5:** The images, replica counts, Services and application configuration stay unchanged. Do not delete and recreate the Deployments: the grader checks that the same workloads are still there.

Run the same command as in the Start section, and compare the output:

```sh
kubectl get deploy -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPL:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image,UID:.metadata.uid | grep -E "mesh-demo|legacy-app|NS"
kubectl get svc -n mesh-demo
kubectl get svc -n legacy-app
```

```text
NS                   NAME                     REPL   IMAGE                                                         UID
legacy-app           billing                  1      nginx:1.27-alpine                                             08f164b3-edd9-42f2-becb-52f253050d5e
mesh-demo            api                      1      nginx:1.27-alpine                                             917084ee-5185-4017-bc0d-32b08a764d7e
mesh-demo            reports                  1      curlimages/curl                                               9387326f-6134-480e-87bc-993e5e31ec8a
NAME   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
api    ClusterIP   10.96.21.179   <none>        80/TCP    20s
NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
billing   ClusterIP   10.96.224.58   <none>        80/TCP    20s
```

The replica counts, the images and the `UID` values are the same as before. The `UID` is the identity of the Deployment object. The same `UID` proves that you restarted the Deployments and did not delete and recreate them.

---

## Submit

Send the lab for grading:

```sh
astrona submit
```

The grader checks the pods, looks for the native sidecar, and asks `istiod` which proxies it sees.

---

## Mistakes That Fail The Grader

- **Labelling the namespace and stopping there (items 1 and 2).** The existing pod was created before the label. Without a restart nothing changes.
- **Deleting and recreating the Deployments (item 5).** The grader checks that the same workloads are still there. Use `rollout restart`.
- **Fixing only the namespace (item 3).** A namespace label cannot override the `false` annotation on the pod template of `reports`.
- **Looking for `istio-proxy` under `containers` (item 1).** On Kubernetes 1.28 and later it is under `initContainers` with `restartPolicy: Always`.
- **Trusting `Running` (item 1).** All pods are `Running`. The `READY` column shows `1/1` where you expect `2/2`, and that is the only sign of the problem.
- **Checking `istioctl proxy-status` too early (item 4).** A new proxy needs a few seconds to connect to `istiod`.
