# Solution Walkthrough

The setup has three faults. The `workloadSelector` of the `ServiceEntry` matches no entry, one `WorkloadEntry` has a misspelled label, and the `ServiceEntry` uses `MESH_EXTERNAL` for machines that you run yourself. A `ServiceEntry` adds a host to the service registry, which is the list of hosts that `istiod`, the Istio control plane, knows about. A `WorkloadEntry` describes one workload that runs outside Kubernetes, for example a virtual machine. The first two faults show up in the sidecar proxy of the `shuttle`. The third one shows up only when you read the object. Items 3 and 4 describe the repaired `ServiceEntry`. Item 5 is the repaired `WorkloadEntry`. Items 1 and 2 prove the result.

---

## Start: Read The Symptom And Find The Three Faults

The task says that every request to the host name fails with `503`. Send one request, and read the last line of the access log of the `shuttle`. The sidecar proxy is the Envoy container that Istio adds to a pod, and its access log has one line for each request. The line is shortened to 260 characters:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1 | cut -c1-260
istioctl analyze -n starfleet
```

```text
503
[2026-10-20T22:14:58.845Z] "GET /hostname HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 1 - "-" "curl/8.11.1" "817a3c07-d7e9-493a-b77b-b64014926815" "freighter.starfleet.mesh:8080" "-" outbound|8080||freighter.starfleet.mesh - 240.240.0.1:8080 10.244.0.6:530

✔ No validation issues found when analyzing namespace: starfleet.
```

The response flag is `UH` ("no healthy upstream"), and the upstream address is `"-"`. The name resolves, and the proxy has the cluster `outbound|8080||freighter.starfleet.mesh`, but the cluster has no endpoint. A cluster is a named destination in Envoy. `istioctl analyze` reports nothing, because a selector that matches nothing is valid configuration. List the endpoints of the cluster, and show the settings of the `ServiceEntry` and the entries side by side:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
kubectl -n starfleet get serviceentry freighter -o jsonpath='{.spec.location} {.spec.resolution} {.spec.workloadSelector.labels}{"\n"}'
kubectl -n starfleet get workloadentry \
  -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,LABELS:.spec.labels,SERVICEACCOUNT:.spec.serviceAccount
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
MESH_EXTERNAL STATIC {"app":"freighters"}
NAME             ADDRESS      LABELS               SERVICEACCOUNT
freighter-vm-1   10.244.0.7   map[app:freighter]   freighter
freighter-vm-2   10.244.0.8   map[app:freigther]   freighter
```

The output shows three faults:

- The selector asks for `app: freighters`. No entry carries that label, so the endpoint list is empty.
- `freighter-vm-2` carries `app: freigther`, with two letters swapped. If you fix only the selector, this machine still has no endpoint.
- The location is `MESH_EXTERNAL`. Requests would work with it, but it tells the mesh that these machines are not part of it. They get no identity, and callers never use mTLS (mutual TLS) toward them, even after the real machines run a sidecar proxy.

Save the state that the rules of the task say must not change:

```sh
kubectl -n starfleet get destinationrule freighter -o jsonpath='generation={.metadata.generation} {.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc
kubectl -n starfleet get pods | awk '{print $1,$2}'
```

```text
generation=1 {"host":"freighter.starfleet.mesh","trafficPolicy":{"tls":{"mode":"DISABLE"}}}
NAME             UID
freighter-vm-1   32c5e16b-1989-4162-afed-2e6c4dd186db
freighter-vm-2   c10c0a23-71fa-418b-b919-0adfe9269082
shuttle          1ff48354-706a-4c99-a227-640b4689240a
No resources found in starfleet namespace.
NAME READY
freighter-vm-1-684c9b8695-xvvp6 1/1
freighter-vm-2-745547488b-x7rsk 1/1
shuttle-7b5db664c-l6z54 2/2
```

The freighter pods show `1/1`, so they have no sidecar proxy, and there is no Service.

---

## Items 3 And 4: Repair The `ServiceEntry`

> **Task item 3:** The `ServiceEntry` named `freighter` has `location: MESH_INTERNAL`. The freighters are your own machines, not somebody else's service.
>
> **Task item 4:** The `ServiceEntry` keeps `resolution: STATIC`, and its `workloadSelector` is exactly `app: freighter`.

Write the whole `ServiceEntry` again, with the correct selector and the correct location. Keep the selector at `app: freighter`, and fix the broken entry in the next step. Save this as `serviceentry-freighter.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: freighter
```

Apply it:

```sh
kubectl apply -f serviceentry-freighter.yaml
```

```text
serviceentry.networking.istio.io/freighter configured
```

Check items 3 and 4. Print the location, the resolution, and the selector:

```sh
kubectl -n starfleet get serviceentry freighter -o jsonpath='{.spec.location} {.spec.resolution} {.spec.workloadSelector}{"\n"}'
```

```text
MESH_INTERNAL STATIC {"labels":{"app":"freighter"}}
```

Now see the effect. Wait a few seconds for `istiod` to send the change to the proxy. Then list the endpoints, and send 10 requests:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname | grep -o 'freighter-vm-[0-9]'
done | sort | uniq -c
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.7:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
  10 freighter-vm-1
```

Requests succeed again, but only `freighter-vm-1` answers. The cluster has one endpoint, because only one entry carries `app: freighter`. If you stopped here, every status code would look fine, and the task would still fail. The `DestinationRule` `freighter` with `tls` mode `DISABLE` is what lets this work with `MESH_INTERNAL`. Without it, the `shuttle` proxy would use mTLS toward pods that have no sidecar proxy, and every request would fail.

---

## Item 5: Repair The Label Of The Second Entry

> **Task item 5:** Both `WorkloadEntry` objects carry the label `app: freighter`, and keep their addresses and the ServiceAccount `freighter`.

Get the address of the second entry, so that you can write the entry again with the same address:

```sh
kubectl -n starfleet get workloadentry freighter-vm-2 -o jsonpath='{.spec.address}{"\n"}'
```

```text
10.244.0.8
```

In the YAML, replace `<FREIGHTER_VM_2>` with that address. Change only the label. Save this as `workloadentry-freighter-vm-2.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: freighter-vm-2
  namespace: starfleet
spec:
  address: <FREIGHTER_VM_2>
  labels:
    app: freighter
  serviceAccount: freighter
```

Apply it:

```sh
kubectl apply -f workloadentry-freighter-vm-2.yaml
```

```text
workloadentry.networking.istio.io/freighter-vm-2 configured
```

Check item 5. Print both entries:

```sh
kubectl -n starfleet get workloadentry \
  -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,LABELS:.spec.labels,SERVICEACCOUNT:.spec.serviceAccount
```

```text
NAME             ADDRESS      LABELS               SERVICEACCOUNT
freighter-vm-1   10.244.0.7   map[app:freighter]   freighter
freighter-vm-2   10.244.0.8   map[app:freighter]   freighter
```

Both entries carry the label `app: freighter`. The addresses and the ServiceAccount are as they were.

---

## Item 1: Exactly Two Endpoints

> **Task item 1:** The `shuttle` sidecar proxy holds **exactly two** endpoints in the cluster `outbound|8080||freighter.starfleet.mesh`: the addresses of the `freighter-vm-1` and `freighter-vm-2` pods.

Wait a few seconds, then list the endpoints again:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.7:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
10.244.0.8:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
```

The cluster has two endpoints, and they are the addresses of the two entries. Your addresses differ.

---

## Item 2: Both Freighters Answer

> **Task item 2:** 20 out of 20 requests from `shuttle` to `http://freighter.starfleet.mesh:8080/hostname` get an answer, and **both** freighter pods answer at least once.

```sh
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname | grep -o 'freighter-vm-[0-9]'
done | sort | uniq -c
```

```text
  13 freighter-vm-1
   7 freighter-vm-2
```

All 20 requests got an answer, and both pods answered. The split differs from run to run.

---

## What Must Not Change

> **Task rules:** Do not change the Deployments and their pods. Do not inject a sidecar proxy into the freighter pods. Do not change the `DestinationRule` named `freighter`. Do not create a Kubernetes Service for the freighter pods.

Run the four commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule freighter -o jsonpath='generation={.metadata.generation} {.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get svc
kubectl -n starfleet get pods | awk '{print $1,$2}'
```

```text
generation=1 {"host":"freighter.starfleet.mesh","trafficPolicy":{"tls":{"mode":"DISABLE"}}}
NAME             UID
freighter-vm-1   32c5e16b-1989-4162-afed-2e6c4dd186db
freighter-vm-2   c10c0a23-71fa-418b-b919-0adfe9269082
shuttle          1ff48354-706a-4c99-a227-640b4689240a
No resources found in starfleet namespace.
NAME READY
freighter-vm-1-684c9b8695-xvvp6 1/1
freighter-vm-2-745547488b-x7rsk 1/1
shuttle-7b5db664c-l6z54 2/2
```

The output is the same as before. The `DestinationRule` still has `generation=1`, the Deployments have the same `UID` values, the freighter pods still show `1/1`, and there is no Service.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-03/labs/lab-02
```

The grader reads the endpoints of the `shuttle` proxy and the objects, and sends requests from the `shuttle`.

---

## Mistakes That Fail The Grader

- **Fixing only the selector (items 1 and 5).** One machine answers, every status code is `200`, and the cluster has one endpoint instead of two.
- **Changing the selector to `app: freigther` to match the broken entry (item 4).** Then `freighter-vm-1` drops out instead. Fix the entry, and keep the selector at `app: freighter`.
- **Leaving `location: MESH_EXTERNAL` (item 3).** Requests work, but machines that you run yourself must be `MESH_INTERNAL`.
- **Deleting the `DestinationRule` (rules).** With `MESH_INTERNAL`, the `shuttle` proxy then uses mTLS toward pods that have no sidecar proxy, and every request fails.
- **Creating a Service for the freighter pods, or injecting a sidecar proxy into them (rules).** The task is to add machines outside the mesh with `WorkloadEntry` objects.
- **Changing the address or the ServiceAccount of an entry (item 5).** They were correct. The address is where the machine is, and the ServiceAccount is its identity.
