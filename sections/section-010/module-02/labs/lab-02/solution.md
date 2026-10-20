# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The Start section finds the cause. Items 1 and 2 are the fix. Items 3 to 6 prove the result and prove that you changed nothing else.

---

## Start: See The Failure And Find The Cause

The task says that `shuttle` gets no response from `probe`, while `cargo` still reaches it. Send a request from `shuttle` and read the last line of the access log of its sidecar proxy. The proxy is the Envoy container that Istio adds to a pod. Wait a moment before you read the log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://probe.outpost:8000/get
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
000
command terminated with exit code 56
[2026-10-20T20:20:40.137Z] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 10.96.170.170:8000 10.244.0.6:50872 - -
```

`000` means that `curl` got no response at all. The log line shows `BlackHoleCluster` and the response flag `UH`. The mesh runs with `outboundTrafficPolicy: REGISTRY_ONLY`, so the proxy sends a request for an unknown host to the `BlackHoleCluster`, which drops it. The `shuttle` proxy has no destination for `probe`.

`cargo` runs in the same namespace and works. Compare the cluster lists of the two proxies. A cluster is a named destination in Envoy:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -E "SERVICE|outpost|istiod|cargo"
istioctl proxy-config cluster deploy/cargo-v1 -n starfleet | grep -E "outpost|istiod"
```

```text
SERVICE FQDN                          PORT     SUBSET     DIRECTION     TYPE             DESTINATION RULE
cargo.starfleet.svc.cluster.local     9080     -          outbound      EDS              
istiod.istio-system.svc.cluster.local     443       -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15010     -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15012     -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15014     -          outbound      EDS              
probe.outpost.svc.cluster.local           8000      -          outbound      EDS              
```

The first command prints two lines: the header and `cargo`. The `shuttle` proxy knows only `cargo`. The second command prints the `istiod` and `probe` clusters, so the `cargo-v1` proxy knows them. Both pods are in the same namespace but have different configuration. A different `Sidecar` object must apply to `shuttle`. List the `Sidecar` objects and print the spec of each:

```sh
kubectl -n starfleet get sidecar
kubectl -n starfleet get sidecar shuttle-only -o jsonpath='{.spec}{"\n"}'
kubectl -n starfleet get sidecar default -o jsonpath='{.spec}{"\n"}'
```

```text
NAME           AGE
default        3s
shuttle-only   3s
{"egress":[{"hosts":["./*"]}],"outboundTrafficPolicy":{"mode":"REGISTRY_ONLY"},"workloadSelector":{"labels":{"app":"shuttle"}}}
{"egress":[{"hosts":["./*","istio-system/*","outpost/*"]}],"outboundTrafficPolicy":{"mode":"REGISTRY_ONLY"}}
```

`shuttle-only` selects the `shuttle` pod, so `istiod`, the Istio control plane, uses it instead of the namespace-wide `default`. A `Sidecar` with a selector replaces the namespace default and takes nothing from it. `shuttle-only` lists only `./*`, so the `shuttle` proxy lost `istio-system` and `outpost`. That is the fault.

Before you fix it, save the identity of the objects that must stay unchanged. Item 6 compares against it:

```sh
kubectl -n starfleet get sidecar default -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
kubectl -n outpost get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
generation=1 uid=ea59e931-445e-48f4-b147-20bd5e88f774
NAME       UID
cargo-v1   8b52d8a5-146c-4f2c-b687-ba7fdce510f2
shuttle    4c28af12-5dd0-428b-81a4-404e2aeb2dfc
NAME    PORT   SELECTOR
cargo   9080   map[app:cargo]
NAME       UID
probe-v1   86cec8b8-acec-4ccc-9187-35b8660a1a6b
probe-v2   826a5fca-f705-4634-b4f7-e924942ae1fe
```

---

## Items 1 And 2: Repair `shuttle-only`

> **Task item 1:** The `Sidecar` **`shuttle-only`** still exists in `starfleet`, still selects only **`app: shuttle`**, and still sets `outboundTrafficPolicy` to **`REGISTRY_ONLY`**.
>
> **Task item 2:** `shuttle-only` lists the pod's **own namespace**, **`istio-system`** and the **`outpost`** namespace in its `egress` hosts.

Both items describe the same object. Item 1 says what you keep, and item 2 says what you add. Keep the selector and `REGISTRY_ONLY`, and list every host that the `shuttle` pod needs. Save this as `sidecar-shuttle-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: shuttle-only
  namespace: starfleet
spec:
  workloadSelector:
    labels:
      app: shuttle
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
    - "outpost/*"
```

Apply it:

```sh
kubectl apply -f sidecar-shuttle-only.yaml
```

```text
sidecar.networking.istio.io/shuttle-only configured
```

Check item 1. Print the selector and the traffic policy:

```sh
kubectl -n starfleet get sidecar shuttle-only -o jsonpath='selector={.spec.workloadSelector} policy={.spec.outboundTrafficPolicy}{"\n"}'
```

```text
selector={"labels":{"app":"shuttle"}} policy={"mode":"REGISTRY_ONLY"}
```

The object selects only `app: shuttle`, and the mode is still `REGISTRY_ONLY`. Check item 2. Print the host list:

```sh
kubectl -n starfleet get sidecar shuttle-only -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
```

```text
["./*","istio-system/*","outpost/*"]
```

The list holds the own namespace, `istio-system` and `outpost`.

---

## Item 3: The Proxy Holds The Clusters Again

> **Task item 3:** The `shuttle` proxy holds clusters for **`probe.outpost.svc.cluster.local`** and **`istiod.istio-system.svc.cluster.local`**.

`istiod` sends the change to the running proxy over xDS, the protocol that `istiod` uses to push configuration to proxies. No pod restarts. Wait a few seconds, then list the clusters:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -E "probe.outpost|istiod.istio-system"
```

```text
istiod.istio-system.svc.cluster.local     443       -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15010     -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15012     -          outbound      EDS              
istiod.istio-system.svc.cluster.local     15014     -          outbound      EDS              
probe.outpost.svc.cluster.local           8000      -          outbound      EDS              
```

Both clusters are back. If the list is empty, wait a few seconds and run the command again.

---

## Item 4: `probe` Answers Through Its Own Cluster

> **Task item 4:** A request from `shuttle` to **`http://probe.outpost:8000/get`** gets **`200`**, and the `shuttle` proxy's access log shows it leaving through **`outbound|8000||probe.outpost.svc.cluster.local`**, not through a passthrough.

Send the request and read the log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe.outpost:8000/get
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
200
[2026-10-20T20:20:51.989Z] "GET /get HTTP/1.1" 200 - via_upstream - "-" 0 655 13 10 "-" "curl/8.11.1" "033e374c-9e42-4499-8f42-61ec85512b51" "probe.outpost:8000" "10.244.0.9:8080" outbound|8000||probe.outpost.svc.cluster.local 10.244.0.6:45780 10.96.170.170:8000 10.244.0.6:52500 - default
```

The status is `200`. The cluster field of the log line is `outbound|8000||probe.outpost.svc.cluster.local`, the cluster of the `probe` Service. It is not `PassthroughCluster` and not `BlackHoleCluster`.

---

## Item 5: `cargo` Is Still Reachable

> **Task item 5:** `shuttle` still reaches `cargo` at **`http://cargo:9080/details/0`** with `200`.

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
```

```text
200
```

The request returns `200`, because `./*` is still in the host list.

---

## Item 6: Nothing Else Changed

> **Task item 6:** Leave the namespace-wide `Sidecar` `default` unchanged, and do not add another `Sidecar` to `starfleet`. Leave the Deployments, pod labels and Services unchanged.

Run the identity commands from the Start section again, and list the `Sidecar` objects:

```sh
kubectl -n starfleet get sidecar
kubectl -n starfleet get sidecar default -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
kubectl -n outpost get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
NAME           AGE
default        15s
shuttle-only   15s
generation=1 uid=ea59e931-445e-48f4-b147-20bd5e88f774
NAME       UID
cargo-v1   8b52d8a5-146c-4f2c-b687-ba7fdce510f2
shuttle    4c28af12-5dd0-428b-81a4-404e2aeb2dfc
NAME    PORT   SELECTOR
cargo   9080   map[app:cargo]
NAME       UID
probe-v1   86cec8b8-acec-4ccc-9187-35b8660a1a6b
probe-v2   826a5fca-f705-4634-b4f7-e924942ae1fe
```

Only the two original `Sidecar` objects exist. The `default` object still has `generation=1`, so nobody edited it. The Deployments have the same `UID` values, and the Services are the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-02/labs/lab-02
```

The grader reads the `Sidecar` objects and the configuration of the `shuttle` proxy, and it sends live requests.

---

## Mistakes That Fail The Grader

- **Deleting `shuttle-only` (item 1).** `probe` becomes reachable through the namespace default, but the task is to repair the `Sidecar` of the `shuttle` pod.
- **Adding only `outpost/*` (item 2).** The `shuttle` proxy still lacks `istio-system/*`. A `Sidecar` with a selector must list it itself.
- **Removing `outboundTrafficPolicy` from `shuttle-only` (item 1).** The pod falls back to `ALLOW_ANY`, and `probe` answers through `PassthroughCluster`. That is not the cluster of the `probe` Service.
- **Changing the namespace default (item 6).** It was correct. Change only `shuttle-only`.
- **Changing the labels of the `shuttle` pod so that the selector no longer matches (item 6).** The grader checks that the pods still carry `app: shuttle`.
