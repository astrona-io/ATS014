# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. One `Sidecar` object answers items 1 and 2. Items 3 to 6 then prove, with the configuration of the proxy and with live requests, that the object does what the task asks. Item 7 proves that you removed nothing.

---

## Start: Measure The Starting Point

The task says that no `Sidecar` resource exists and that all three backends answer. You cannot show that the configuration got smaller without a number to compare against, so measure first. A cluster is a destination in the configuration of an Envoy proxy, and `istioctl proxy-config cluster` lists the clusters:

```sh
kubectl get sidecar -A
istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -E 'sidecar-other|sidecar-third'
```

```text
No resources found
      29
httpbin.sidecar-other.svc.cluster.local                        8000      -          outbound      EDS              
httpbin.sidecar-third.svc.cluster.local                        8000      -          outbound      EDS              
```

There is no `Sidecar` object. The proxy of `tester` holds 29 lines, including the header line, and it has clusters for both other namespaces. This is the mesh default: `istiod`, the Istio control plane, gives every proxy every host of the service registry.

Now test the three backends from `tester`:

```sh
for url in http://local-backend:8000/get \
           http://httpbin.sidecar-other:8000/get \
           http://httpbin.sidecar-third:8000/get; do
  printf '%s -> ' "$url"
  kubectl -n sidecar-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url"
done
```

```text
http://local-backend:8000/get -> 200
http://httpbin.sidecar-other:8000/get -> 200
http://httpbin.sidecar-third:8000/get -> 200
```

All three answer, because every proxy knows every host. Save the identity of the workloads, the Services and the namespaces. Item 7 compares against it:

```sh
for ns in sidecar-demo sidecar-other sidecar-third; do
  echo "-- $ns"
  kubectl -n $ns get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
  kubectl -n $ns get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
done
kubectl get namespace sidecar-demo sidecar-other sidecar-third -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
-- sidecar-demo
NAME            REPL   UID
local-backend   1      7bb29f74-1ce7-44f4-a15a-3695cf8f9cfc
tester          1      ad960bf8-6ca3-482a-9b43-fdb5443cfce1
NAME            PORT
local-backend   8000
-- sidecar-other
NAME      REPL   UID
httpbin   1      f988951d-5466-4888-bd3e-8753ee67645e
NAME      PORT
httpbin   8000
-- sidecar-third
NAME      REPL   UID
httpbin   1      e7c6453a-1ea9-472d-8148-4656295624f4
NAME      PORT
httpbin   8000
NAME            UID
sidecar-demo    ff1450d1-d3d7-43fe-8d2d-8e7aabddc7ba
sidecar-other   d06a0a67-1700-4c86-8ae5-e5cdf6afa3a3
sidecar-third   f2901307-5175-466d-8aed-9330026f1922
```

---

## Items 1 And 2: Write The `Sidecar`

> **Task item 1:** Create a `Sidecar` resource named **`default`** in the namespace **`sidecar-demo`** that applies to **every workload in that namespace**. Do not use a `workloadSelector`.
>
> **Task item 2:** Limit its `egress` hosts to exactly three things: the proxy's **own namespace**, **`istio-system`**, and **`sidecar-other`**.

A `Sidecar` resource limits which hosts the sidecar proxies of a namespace know about. The two items describe one object, so you write it once. Save this as `sidecar-default.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: sidecar-demo
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
        - "sidecar-other/*"
```

Apply it:

```sh
kubectl apply -f sidecar-default.yaml
```

```text
sidecar.networking.istio.io/default created
```

Each part of the object answers a part of the task:

- **The name `default` and no `workloadSelector` (item 1).** Leaving out the selector is how you say "every workload in the namespace". A selector for `app: tester` would leave the proxy of `local-backend` unchanged.
- **`./*` (item 2).** This is the namespace of the proxy itself. It keeps `local-backend` reachable.
- **`istio-system/*` (item 2).** This keeps the destinations of the control plane. Without it, parts of the mesh fail in ways that never point back at this object.
- **`sidecar-other/*` (item 2).** This is the one other namespace that must stay.

`sidecar-third` is not in the list, and that is the whole mechanism. A `Sidecar` has no field that denies a host. A host that is not listed is not sent to the proxy.

Check item 1. Print the object, and print its `workloadSelector`, which must be empty:

```sh
kubectl -n sidecar-demo get sidecar
kubectl -n sidecar-demo get sidecar default -o jsonpath='workloadSelector=[{.spec.workloadSelector}]{"\n"}'
```

```text
NAME      AGE
default   6s
workloadSelector=[]
```

There is one `Sidecar` named `default`, and it has no selector. Check item 2. Print the host list:

```sh
kubectl -n sidecar-demo get sidecar default -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
```

```text
["./*","istio-system/*","sidecar-other/*"]
```

Exactly three entries are in the list.

---

## Item 3: `sidecar-third` Is Gone From The Proxy

> **Task item 3:** `sidecar-third` must **not** be in the `tester` proxy's configuration, and must not be reachable from `tester`.

`istiod` sends the change to the running proxy. No pod restarts. Wait a few seconds, then count the lines about `sidecar-third` in the cluster list. Then send a request to it:

```sh
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -c sidecar-third
kubectl -n sidecar-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://httpbin.sidecar-third:8000/get
```

```text
0
502
```

The cluster list holds no line for `sidecar-third`. The request fails with `502`. You may see `000` instead, which is how `curl` reports that it got no HTTP response. The task says the mesh runs with `outboundTrafficPolicy: REGISTRY_ONLY`. A host that is not in the configuration of the proxy therefore fails, and the request does not leave through a passthrough. If the count is still above `0`, wait a few seconds and run the command again.

---

## Item 4: `sidecar-other` Is Still Reachable

> **Task item 4:** `sidecar-other` must still be reachable from `tester`: `http://httpbin.sidecar-other:8000/get` must return `HTTP 200`.

```sh
kubectl -n sidecar-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://httpbin.sidecar-other:8000/get
```

```text
200
```

The request returns `200`, because `sidecar-other/*` is in the host list.

---

## Item 5: The Local Backend Is Still Reachable

> **Task item 5:** `local-backend` in the proxy's own namespace must still be reachable.

```sh
kubectl -n sidecar-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://local-backend:8000/get
```

```text
200
```

The request returns `200`, because `./*` is in the host list.

---

## Item 6: The Cluster List Is Smaller

> **Task item 6:** The `tester` proxy's cluster list must be clearly smaller than before.

Measure again, and compare with the 29 lines from the Start section:

```sh
istioctl proxy-config cluster deploy/tester -n sidecar-demo | wc -l
istioctl proxy-config cluster deploy/tester -n sidecar-demo | grep -E 'sidecar-other|local-backend'
```

```text
      25
httpbin.sidecar-other.svc.cluster.local                        8000      -          outbound      EDS              
local-backend.sidecar-demo.svc.cluster.local                   8000      -          outbound      EDS              
```

The list went from 29 lines to 25, and the two hosts that you kept are still there. The drop is small, because this cluster has only a few Services. The `istio-system/*` entry keeps the destinations of the control plane. In a real mesh with hundreds of Services, the same object removes far more.

---

## Item 7: Nothing Else Changed

> **Task item 7:** Leave the Deployments, Services and namespaces unchanged. Do not delete `sidecar-third` or its workload: the `Sidecar` must stop the traffic, not the removal of the target.

Run the identity commands from the Start section again:

```sh
for ns in sidecar-demo sidecar-other sidecar-third; do
  echo "-- $ns"
  kubectl -n $ns get deploy -o custom-columns=NAME:.metadata.name,REPL:.spec.replicas,UID:.metadata.uid
  kubectl -n $ns get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port
done
kubectl get namespace sidecar-demo sidecar-other sidecar-third -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
-- sidecar-demo
NAME            REPL   UID
local-backend   1      7bb29f74-1ce7-44f4-a15a-3695cf8f9cfc
tester          1      ad960bf8-6ca3-482a-9b43-fdb5443cfce1
NAME            PORT
local-backend   8000
-- sidecar-other
NAME      REPL   UID
httpbin   1      f988951d-5466-4888-bd3e-8753ee67645e
NAME      PORT
httpbin   8000
-- sidecar-third
NAME      REPL   UID
httpbin   1      e7c6453a-1ea9-472d-8148-4656295624f4
NAME      PORT
httpbin   8000
NAME            UID
sidecar-demo    ff1450d1-d3d7-43fe-8d2d-8e7aabddc7ba
sidecar-other   d06a0a67-1700-4c86-8ae5-e5cdf6afa3a3
sidecar-third   f2901307-5175-466d-8aed-9330026f1922
```

The output is the same as before. The `httpbin` workload in `sidecar-third` still runs with one replica, and its `UID` has not changed. The `Sidecar` stopped the traffic, and nothing was deleted.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-01
```

The grader reads the configuration of the `tester` proxy and sends live requests.

---

## Mistakes That Fail The Grader

- **Leaving out `istio-system/*` (item 2).** Requests inside the namespace keep working, so a quick test hides the mistake. Connections to the control plane do not work.
- **Adding a `workloadSelector` (item 1).** The task asks for the whole namespace. With a selector, the proxy of `local-backend` keeps the full registry.
- **Using `*/*` (item 2).** That is the default written down. Nothing gets smaller.
- **Creating a second `Sidecar` (item 1).** Two namespace-wide `Sidecar` objects do not merge, and the result is not defined. Keep exactly one.
- **Deleting `sidecar-third` or scaling it to zero (item 7).** The grader checks that it still runs.
- **Patching `hosts` and expecting it to add entries (item 2).** A merge patch replaces the whole list. Write every host that you want to keep.
- **Testing straight after applying (items 3 to 6).** The push takes a moment. If the cluster list has not changed, wait a few seconds before you decide that the object is wrong.
