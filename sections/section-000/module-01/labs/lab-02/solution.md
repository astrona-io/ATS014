# Solution Walkthrough

This walkthrough follows the task from top to bottom. The Start section finds the fault. Item 1 fixes it, and each later item proves one more part of the result.

---

## Start: Find The Fault

The task says that the `bridge` page shows "Error fetching product details" and that every request to `cargo` fails with `503`. Confirm both from the `shuttle` pod:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
```

```text
Error fetching product details
503
```

The task also says that every Deployment is running. Look at the Deployments and Services:

```sh
kubectl -n starfleet get deploy,svc
```

```text
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/bridge-v1   1/1     1            1           44s
deployment.apps/cargo-v1    1/1     1            1           44s
deployment.apps/navcom-v1   1/1     1            1           44s
deployment.apps/scout-v1    1/1     1            1           44s
deployment.apps/scout-v2    1/1     1            1           44s
deployment.apps/scout-v3    1/1     1            1           44s
deployment.apps/shuttle     1/1     1            1           44s

NAME             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/bridge   ClusterIP   10.96.94.66    <none>        9080/TCP   44s
service/cargo    ClusterIP   10.96.53.107   <none>        9080/TCP   44s
service/navcom   ClusterIP   10.96.79.128   <none>        9080/TCP   44s
service/scout    ClusterIP   10.96.25.76    <none>        9080/TCP   44s
```

Every object exists and every Deployment is ready, so `kubectl get` shows no problem. Read what happened to the failed request in the access log of the `shuttle` sidecar proxy. The proxy is the Envoy container that Istio adds to each pod, and it writes one line per request. Wait a moment before you read the log:

```sh
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
[2026-10-20T20:00:02.338Z] "GET /details/0 HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 0 - "-" "curl/8.11.1" "fba8efc3-2d07-481b-9846-5b7068447fa7" "cargo:9080" "-" outbound|9080||cargo.starfleet.svc.cluster.local - 10.96.53.107:9080 10.244.0.12:44634 - default
```

The response flag is `UH`, which means "no healthy upstream". The proxy knows the destination `outbound|9080||cargo…`, but the destination holds no pod. The upstream address in the line is `"-"`, because there was no pod to choose.

Now ask for the endpoints. An endpoint is the address of one pod behind a Service. Ask the proxy, and ask Kubernetes for the EndpointSlice, the object that lists the pod addresses behind a Service:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
kubectl -n starfleet get endpointslices -l kubernetes.io/service-name=cargo
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
NAME          ADDRESSTYPE   PORTS     ENDPOINTS   AGE
cargo-zn7gv   IPv4          <unset>   <unset>     46s
```

Both are empty. A Service finds its pods with its selector, so compare the selector with the labels of the `cargo` pod:

```sh
kubectl -n starfleet get service cargo -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n starfleet get pods --show-labels | grep cargo
```

```text
{"app":"carg0"}
cargo-v1-6f787f8bd5-qsjc4    2/2     Running   0          46s   app=cargo,pod-template-hash=6f787f8bd5,security.istio.io/tlsMode=istio,service.istio.io/canonical-name=cargo,service.istio.io/canonical-revision=v1,version=v1
```

This is the fault. The Service selects `app=carg0`, with a zero. The pod carries `app=cargo`. Kubernetes accepts a selector that matches no pod, so nothing reported an error.

Before you fix anything, save the identity of the Deployments and the labels of the pods. Item 5 compares against them:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,APP:.metadata.labels.app
```

```text
NAME        UID
bridge-v1   2fc2c451-0fad-464c-a5e3-f0bfdfd179a6
cargo-v1    192327c6-7465-4629-8811-1ad76f8a6d89
navcom-v1   c7a8f4f8-7dc9-433d-a6a9-4fbfb2d807e8
scout-v1    d041bc94-2131-43a0-b13d-6fa731835600
scout-v2    f23e5f0f-a16a-4ccd-8826-6f7c70c1d7b1
scout-v3    ff7f13e9-8062-404b-b5db-5a01da64a550
shuttle     53bc5257-1593-4d8e-baad-ece556d4d2fe
NAME                         APP
bridge-v1-bc4dc4fcc-hnzxh    bridge
cargo-v1-6f787f8bd5-qsjc4    cargo
navcom-v1-7467bbc689-w5jfb   navcom
scout-v1-85bf65868-lv2tx     scout
scout-v2-866c98b568-grlz8    scout
scout-v3-668c6dfc68-k5dl7    scout
shuttle-7b5db664c-ltksb      shuttle
```

---

## Item 1: Make The Service Select The `cargo` Pods Again

> **Task item 1:** The `cargo` Service in `starfleet` selects the `cargo` pods again, on port `9080`.

The fix is one value in the Service, so a short patch is enough. The task says the fix belongs in the Service, not in the pods:

```sh
kubectl -n starfleet patch service cargo --type merge \
  -p '{"spec":{"selector":{"app":"cargo"}}}'
```

```text
service/cargo patched
```

Check item 1. Print the selector and the port of the Service:

```sh
kubectl -n starfleet get service cargo -o jsonpath='selector={.spec.selector} port={.spec.ports[0].port}{"\n"}'
```

```text
selector={"app":"cargo"} port=9080
```

The selector is `app: cargo` and the port is still `9080`.

---

## Item 2: The `shuttle` Proxy Holds A Healthy Endpoint

> **Task item 2:** The `shuttle` sidecar proxy holds at least one healthy endpoint in the cluster `outbound|9080||cargo.starfleet.svc.cluster.local`. In Envoy, a cluster is a named destination, and its endpoints are the pod addresses behind it.

`istiod`, the Istio control plane, sends the new endpoint to every proxy. Wait a few seconds, then ask the `shuttle` proxy again:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:9080     HEALTHY     OK                outbound|9080||cargo.starfleet.svc.cluster.local
```

The cluster holds one endpoint, and its status is `HEALTHY`. If the list is still empty, wait a few seconds and run the command again.

---

## Item 3: Ten Of Ten Requests Return `200`

> **Task item 3:** All 10 out of 10 requests from `shuttle` to `http://cargo:9080/details/0` return `200`.

Send 10 requests and count the status codes:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
done | sort | uniq -c
```

```text
  10 200
```

All 10 requests returned `200`.

---

## Item 4: The `bridge` Page Shows The Product Details

> **Task item 4:** The `bridge` page (`http://bridge:9080/productpage`, fetched from `shuttle`) shows the product details: it contains `ISBN-10`, and no longer says "Error fetching product details".

Fetch the page again and search for the two texts:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
```

```text
ISBN-10
```

The page contains `ISBN-10`, and the error text is gone.

---

## Item 5: Nothing Else Changed

> **Task item 5:** The Deployments and their pod labels stay unchanged. Do not add or remove workloads. The fix belongs in the Service that selects the pods, not in the pods.

Run the two commands from the Start section again, and compare the output:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,APP:.metadata.labels.app
```

```text
NAME        UID
bridge-v1   2fc2c451-0fad-464c-a5e3-f0bfdfd179a6
cargo-v1    192327c6-7465-4629-8811-1ad76f8a6d89
navcom-v1   c7a8f4f8-7dc9-433d-a6a9-4fbfb2d807e8
scout-v1    d041bc94-2131-43a0-b13d-6fa731835600
scout-v2    f23e5f0f-a16a-4ccd-8826-6f7c70c1d7b1
scout-v3    ff7f13e9-8062-404b-b5db-5a01da64a550
shuttle     53bc5257-1593-4d8e-baad-ece556d4d2fe
NAME                         APP
bridge-v1-bc4dc4fcc-hnzxh    bridge
cargo-v1-6f787f8bd5-qsjc4    cargo
navcom-v1-7467bbc689-w5jfb   navcom
scout-v1-85bf65868-lv2tx     scout
scout-v2-866c98b568-grlz8    scout
scout-v3-668c6dfc68-k5dl7    scout
shuttle-7b5db664c-ltksb      shuttle
```

The output is the same as before the fix. The same seven Deployments exist with the same `UID` values, and the pod names and the `app` labels are the same. The pod `cargo-v1-6f787f8bd5-qsjc4` still carries `app: cargo`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-000/module-01/labs/lab-02
```

The grader reads the `cargo` Service, the configuration in the `shuttle` proxy, and live requests from `shuttle`.

---

## Mistakes That Fail The Grader

- **Relabelling the `cargo` pod to `app: carg0` (items 1 and 5).** The `bridge` page would work, but the pods were never the problem. The grader checks that the pods still carry `app: cargo`.
- **Deleting and recreating the Service with a different port (item 1).** The grader expects port `9080`.
- **Stopping at `istioctl analyze` (Start).** It stays clean the whole time, because there are no Istio objects. The `UH` flag and the empty endpoint list point at the Service.
- **Testing straight after the patch (items 2 and 3).** `istiod` needs a few seconds to send the new endpoint to the `shuttle` proxy. Wait, then check again.
