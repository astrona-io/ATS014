# Solution Walkthrough

Every pod in this lab was fine. The `cargo` Service selected pods by a label that no pod carries. So the Service had no endpoints, and every request to it had no pod to go to. The steps below follow the fixed order of checks: `kubectl get`, `istioctl analyze`, the access log, then `istioctl proxy-config`.

---

## Step 1: Does It Exist?

Start at the top of the checks. Confirm the failure on the `bridge` page:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
```

```text
Error fetching product details
```

Then list the Deployments and Services:

```sh
kubectl -n starfleet get deploy,svc
```

```text
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/bridge-v1   1/1     1            1           75s
deployment.apps/cargo-v1    1/1     1            1           75s
deployment.apps/navcom-v1   1/1     1            1           75s
deployment.apps/scout-v1    1/1     1            1           75s
deployment.apps/scout-v2    1/1     1            1           75s
deployment.apps/scout-v3    1/1     1            1           75s
deployment.apps/shuttle     1/1     1            1           75s

NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/bridge   ClusterIP   10.96.102.2     <none>        9080/TCP   75s
service/cargo    ClusterIP   10.96.157.127   <none>        9080/TCP   75s
service/navcom   ClusterIP   10.96.235.205   <none>        9080/TCP   75s
service/scout    ClusterIP   10.96.4.24      <none>        9080/TCP   75s
```

Every object exists, and every Deployment is ready. `kubectl get` cannot show this problem.

## Step 2: Do The Objects Agree?

Run Istio's checks across the objects in the namespace:

```sh
istioctl analyze -n starfleet
```

```text
✔ No validation issues found when analyzing namespace: starfleet.
```

The result is clean, because there are no Istio objects to check against each other. A clean result is not a proof: the problem is further down the list of checks.

## Step 3: What Really Happened To The Request?

Send one request to `cargo`, wait a second, and read the last line of the `shuttle` access log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T20:06:53.230Z] "GET /details/0 HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 0 - "-" "curl/8.11.1" "b4709687-2435-427d-8cfe-bc70757879ae" "cargo:9080" "-" outbound|9080||cargo.starfleet.svc.cluster.local - 10.96.157.127:9080 10.244.0.12:43192 - default
```

The response flag is **`UH`**, "no healthy upstream". The proxy knows the destination `outbound|9080||cargo…`, but the destination holds no pod. The upstream address is `"-"`: there was no pod to choose. This is a destination problem, not a routing problem.

## Step 4: What Does The Proxy Hold?

Ask the `shuttle` proxy for the endpoints in the `cargo` cluster, and ask Kubernetes for the `cargo` EndpointSlice (the object that lists the pod addresses behind a Service):

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
kubectl -n starfleet get endpointslices -l kubernetes.io/service-name=cargo
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
NAME          ADDRESSTYPE   PORTS     ENDPOINTS   AGE
cargo-mgzfg   IPv4          <unset>   <unset>     78s
```

Both are empty. The `cargo` pod is running, but the `cargo` Service has no endpoints. A Service gets its endpoints from its selector, so compare the selector with the labels of the `cargo` pod:

```sh
kubectl -n starfleet get service cargo -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n starfleet get pods --show-labels | grep cargo
```

```text
{"app":"carg0"}
cargo-v1-6f787f8bd5-24jvp    2/2     Running   0          78s   app=cargo,pod-template-hash=6f787f8bd5,security.istio.io/tlsMode=istio,service.istio.io/canonical-name=cargo,service.istio.io/canonical-revision=v1,version=v1
```

This is the cause: the Service selects `app=carg0`, with a zero, and the pod carries `app=cargo`. Kubernetes accepts a selector that matches no pod, so nothing reported an error.

## Step 5: Fix The Service Selector

The fix is one value in the Service, so a short `kubectl patch` is enough:

```sh
kubectl -n starfleet patch service cargo --type merge \
  -p '{"spec":{"selector":{"app":"cargo"}}}'
```

```text
service/cargo patched
```

## Step 6: Prove It

Wait a few seconds, then check the proxy, a request, and the `bridge` page:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:9080     HEALTHY     OK                outbound|9080||cargo.starfleet.svc.cluster.local
200
ISBN-10
```

The `cargo` cluster holds a healthy endpoint again, the request returns `200`, and the `bridge` page shows the product details. Submit:

```sh
astrona submit -c sections/section-000/module-01/labs/lab-02
```

```text
PASS: the cargo Service selects the cargo ships again, the shuttle's proxy holds a healthy cargo endpoint, 10 of 10 signals to cargo answered 200, and the bridge page shows the product details
```

---

## Mistakes that fail the grader

- **Relabelling the `cargo` pods to `app: carg0`.** The `bridge` page would work, but the pods were never the problem. The grader checks that the pods still carry `app: cargo`.
- **Deleting and recreating the Service with a different port.** The grader expects port `9080`.
- **Stopping at `istioctl analyze`.** It stays clean the whole time. The `UH` flag and the empty endpoint list point at the Service.
- **Testing straight after the patch.** `istiod` needs a few seconds to push the new endpoint to the `shuttle` proxy. Wait, then check again.
