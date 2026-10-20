# Solution Walkthrough

The task needs four objects: two `WorkloadEntry` objects (one for each machine), one `ServiceEntry` (the host name in front of them) and one `WorkloadGroup` (the template for real machines). A `WorkloadEntry` describes one workload that runs outside Kubernetes, for example a virtual machine, so the mesh can route to it. The field that decides whether the task passes is `location` in the `ServiceEntry`. Item 1 is the two `WorkloadEntry` objects. Item 2 is the `ServiceEntry`, and items 5 to 8 prove it. Item 3 is the `WorkloadGroup`, and item 9 proves it. Items 4 and 10 close the walkthrough.

---

## Start: See What The Mesh Knows Today

The task says that the mesh knows nothing about the two machines. Read the two addresses, list the pods, and send one request by IP address and one by host name. Then count the clusters for the machines in the sidecar proxy of `tester`. The sidecar proxy is the Envoy container that Istio adds to a pod, and a cluster is a named destination in Envoy with a list of endpoints:

```sh
VM1=$(cat /tmp/vm1-ip)
VM2=$(cat /tmp/vm2-ip)
echo "vm1=$VM1  vm2=$VM2"
kubectl -n vm-demo get pods -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by address: %{http_code}\n" --max-time 10 "http://$VM1:8080/get"
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name:    %{http_code}\n" --max-time 10 "http://legacy.vm-demo.svc:8080/get"
istioctl proxy-config cluster deploy/tester -n vm-demo | grep -c legacy
kubectl -n vm-demo get workloadentry,serviceentry,workloadgroup
kubectl -n vm-demo get destinationrule
kubectl -n vm-demo get svc
```

```text
vm1=10.244.0.8  vm2=10.244.0.9
NAME READY STATUS IP
legacy-vm-1 1/1 Running 10.244.0.8
legacy-vm-2 1/1 Running 10.244.0.9
tester-69699fd775-4fd8l 2/2 Running 10.244.0.10
by address: 200
by name:    000
command terminated with exit code 6
0
No resources found in vm-demo namespace.
NAME               HOST                 AGE
legacy-plaintext   legacy.vm-demo.svc   1s
No resources found in vm-demo namespace.
```

Both machines answer by IP address. The host name does not resolve, so `curl` prints `000` with the exit code `6`. The `tester` proxy has zero clusters for the machines. They are not in the service registry, which is the list of hosts that `istiod`, the Istio control plane, knows about. So no policy, no telemetry and no host name applies to them. The `READY` column shows `1/1` for the machines and `2/2` for `tester`. The stand-in pods have no sidecar proxy, and that is what makes them behave like machines outside the mesh. The `DestinationRule` `legacy-plaintext` belongs to the environment and stays in place.

---

## Item 1: Describe Both Machines

> **Task item 1:** Create **two** `WorkloadEntry` objects in `vm-demo`, named **`legacy-vm-1`** and **`legacy-vm-2`**, each with:
>
> * `address` set to the IP address of the matching machine
> * the label **`app: legacy-backend`**
> * `serviceAccount` **`legacy-sa`**. This field gives the workload its identity in the mesh.

Each machine needs its own `WorkloadEntry`. Replace `<VM1>` with the address that `echo $VM1` prints. Save this as `workloadentry-legacy-vm-1.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-1
  namespace: vm-demo
spec:
  address: <VM1>
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
```

Apply it:

```sh
kubectl apply -f workloadentry-legacy-vm-1.yaml
```

Do the same for the second machine. Replace `<VM2>` with the address that `echo $VM2` prints. Save this as `workloadentry-legacy-vm-2.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-2
  namespace: vm-demo
spec:
  address: <VM2>
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
```

Apply it:

```sh
kubectl apply -f workloadentry-legacy-vm-2.yaml
```

```text
workloadentry.networking.istio.io/legacy-vm-1 created
workloadentry.networking.istio.io/legacy-vm-2 created
```

You write the addresses into the entries yourself. That is the practical difference from a pod: Kubernetes records the address of a pod for you, but nobody does that for a machine outside Kubernetes. The same label `app: legacy-backend` on both entries makes them one service in the next step. The field `serviceAccount: legacy-sa` gives each machine the SPIFFE (Secure Production Identity Framework For Everyone) identity `spiffe://cluster.local/ns/vm-demo/sa/legacy-sa`. A pod that runs as that ServiceAccount has the same identity. That is why an `AuthorizationPolicy` can name these machines.

Check item 1. Print the address, the labels and the ServiceAccount of each entry:

```sh
kubectl -n vm-demo get workloadentry \
  -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,LABELS:.spec.labels,SA:.spec.serviceAccount
```

```text
NAME          ADDRESS      LABELS                    SA
legacy-vm-1   10.244.0.8   map[app:legacy-backend]   legacy-sa
legacy-vm-2   10.244.0.9   map[app:legacy-backend]   legacy-sa
```

The entries alone change nothing that you can see yet: a `WorkloadEntry` has no host name and no service port.

---

## Item 2: Give The Machines One Host Name

> **Task item 2:** Create a `ServiceEntry` named **`legacy`** in `vm-demo` for the host **`legacy.vm-demo.svc`**, with:
>
> * `location` **`MESH_INTERNAL`**, because these are your own workloads, not somebody else's service
> * `resolution` **`STATIC`**
> * one port: number **8080**, name `http`, protocol **`HTTP`**
> * a `workloadSelector` that matches the label **`app: legacy-backend`**

A `ServiceEntry` adds a host to the service registry. Its `workloadSelector` selects the entries by label, the same way a Kubernetes Service selects pods. Save this as `serviceentry-legacy.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: legacy
  namespace: vm-demo
spec:
  hosts:
    - legacy.vm-demo.svc
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  workloadSelector:
    labels:
      app: legacy-backend
```

Apply it:

```sh
kubectl apply -f serviceentry-legacy.yaml
```

```text
serviceentry.networking.istio.io/legacy created
```

Three fields differ from a `ServiceEntry` for the service of somebody else:

- `location: MESH_INTERNAL`. These are your own workloads. This setting makes the identity count, makes callers use mTLS (mutual TLS) toward them, and lets an `AuthorizationPolicy` name them. `MESH_EXTERNAL` would also give you a working host name, but none of the rest, and the requests look fine either way.
- `resolution: STATIC`. The entries already hold the addresses, so there is nothing to look up.
- `workloadSelector`. It links the host to the entries by label.

Because the location is `MESH_INTERNAL`, the `tester` proxy would use mTLS toward the machines, and the stand-in pods cannot accept it. The `DestinationRule` `legacy-plaintext`, which belongs to the environment, sets `tls` mode `DISABLE` for this host, so the requests use plain HTTP. A real virtual machine would not need it.

Check item 2. Print the spec:

```sh
kubectl -n vm-demo get serviceentry legacy -o jsonpath='{.spec}{"\n"}'
```

```text
{"hosts":["legacy.vm-demo.svc"],"location":"MESH_INTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"}],"resolution":"STATIC","workloadSelector":{"labels":{"app":"legacy-backend"}}}
```

---

## Items 5 And 6: The Fields That The Grader Reads

> **Task item 5:** The `ServiceEntry` has `location: MESH_INTERNAL`. `MESH_EXTERNAL` routes requests too, but gives the workloads no identity, so the grader does not accept it.
>
> **Task item 6:** `resolution` is `STATIC`, the port is `8080` with protocol `HTTP`, and the `workloadSelector` matches the label of the entries.

The spec in item 2 shows all of it: `location` is `MESH_INTERNAL`, `resolution` is `STATIC`, the port is `8080` with the protocol `HTTP`, and the `workloadSelector` has the label `app: legacy-backend`, the same label as both entries.

---

## Item 7: The Host Name Resolves

> **Task item 7:** `GET http://legacy.vm-demo.svc:8080/get` from `tester` returns **200**. The host name resolves, which it did not before.

`istiod` sends the new entry to the proxy. Wait a few seconds, then send the request:

```sh
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name: %{http_code}\n" --max-time 10 http://legacy.vm-demo.svc:8080/get
```

```text
by name: 200
```

At the start, the same request printed `000`.

---

## Item 8: Two Endpoints In The Cluster

> **Task item 8:** The cluster for `legacy.vm-demo.svc` in the `tester` sidecar proxy has **two** endpoints, one per machine.

List the cluster and its endpoints in the `tester` proxy:

```sh
istioctl proxy-config cluster deploy/tester -n vm-demo | grep -E "SERVICE|legacy"
istioctl proxy-config endpoints deploy/tester -n vm-demo --cluster "outbound|8080||legacy.vm-demo.svc"
```

```text
SERVICE FQDN                                                   PORT      SUBSET     DIRECTION     TYPE             DESTINATION RULE
legacy.vm-demo.svc                                             8080      -          outbound      EDS              legacy-plaintext.vm-demo
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8080     HEALTHY     OK                outbound|8080||legacy.vm-demo.svc
10.244.0.9:8080     HEALTHY     OK                outbound|8080||legacy.vm-demo.svc
```

The cluster has two endpoints, one for each machine, joined by the shared label. The `TYPE` is `EDS` (Endpoint Discovery Service), and not `STATIC`. The `ServiceEntry` selects its endpoints with `workloadSelector`, so `istiod` sends the endpoint list to the proxy separately, the same way as for a Kubernetes Service. The last column shows that the `DestinationRule` `legacy-plaintext` applies to this cluster. Load balancing, outlier detection and locality settings apply to the machines now, the same way as to two pods. If you see only one endpoint, one of the entries has a different label than the selector.

---

## Item 3: The `WorkloadGroup` For Real Machines

> **Task item 3:** Create a `WorkloadGroup` named **`legacy`** in `vm-demo` whose template matches those entries: labels `app: legacy-backend`, `serviceAccount` `legacy-sa`, port `http: 8080`. No machine registers against it here, because the stand-in pods do not run `istio-agent`, but a real group of virtual machines needs it.

A `WorkloadGroup` describes what every machine of one service looks like: labels, ServiceAccount and ports, but no address. Save this as `workloadgroup-legacy.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: legacy
  namespace: vm-demo
spec:
  metadata:
    labels:
      app: legacy-backend
  template:
    serviceAccount: legacy-sa
    ports:
      http: 8080
```

Apply it:

```sh
kubectl apply -f workloadgroup-legacy.yaml
```

```text
workloadgroup.networking.istio.io/legacy created
```

Check item 3 and item 9. List the group and the entries, and print the spec of the group:

```sh
kubectl -n vm-demo get workloadgroup,workloadentry
kubectl -n vm-demo get workloadgroup legacy -o jsonpath='{.spec}{"\n"}'
```

```text
NAME                                       AGE
workloadgroup.networking.istio.io/legacy   0s

NAME                                            AGE   ADDRESS
workloadentry.networking.istio.io/legacy-vm-1   13s   10.244.0.8
workloadentry.networking.istio.io/legacy-vm-2   13s   10.244.0.9
{"metadata":{"labels":{"app":"legacy-backend"}},"template":{"ports":{"http":8080},"serviceAccount":"legacy-sa"}}
```

---

## Item 9: The Template Matches The Entries

> **Task item 9:** The `WorkloadGroup` exists, and the labels, ServiceAccount and port of its template match the entries.

The spec of the group has the label `app: legacy-backend`, the ServiceAccount `legacy-sa` and the port `http: 8080`. These are the same values as in the entries and in the `ServiceEntry`. There are still only the two entries that you wrote. No third entry appears, and none will here. A real virtual machine runs `istio-agent`, the Istio program that starts its sidecar proxy, connects to `istiod` with a ServiceAccount token, and registers against the group. Then `istiod` creates the `WorkloadEntry` from exactly these values, with the address taken from the machine itself. A `WorkloadGroup` relates to `WorkloadEntry` objects the way a Deployment relates to Pods.

---

## Item 4: Both Entries Are Correct

> **Task item 4:** Both `WorkloadEntry` objects exist with the correct address, label and ServiceAccount.

The table in item 1 shows it: the addresses `10.244.0.8` and `10.244.0.9` match the files `/tmp/vm1-ip` and `/tmp/vm2-ip`, both entries have the label `app: legacy-backend`, and both have the ServiceAccount `legacy-sa`.

---

## Item 10: The Stand-In Pods Are Unchanged

> **Task item 10:** Both stand-in pods still run without a sidecar proxy, and no Service was created for them.

```sh
kubectl -n vm-demo get pods | awk '{print $1,$2,$3}'
kubectl -n vm-demo get svc
```

```text
NAME READY STATUS
legacy-vm-1 1/1 Running
legacy-vm-2 1/1 Running
tester-69699fd775-4fd8l 2/2 Running
No resources found in vm-demo namespace.
```

The machines show `1/1`, so they still have no sidecar proxy, and no Service exists. A Service would add the pods to the registry in another way.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-03/labs/lab-01
```

The grader reads the objects and the cluster of the `tester` proxy, and sends requests from `tester`.

---

## Mistakes That Fail The Grader

- **`location: MESH_EXTERNAL` (items 2 and 5).** Requests are routed, but the machines get no identity. This is the most likely way to fail while it looks like it works.
- **`resolution: DNS` (items 2 and 6).** The entries already hold the addresses, so the task asks for `STATIC`.
- **Labels that do not match (items 1, 2 and 8).** The `workloadSelector` and the `labels` of the entries must agree. Otherwise the cluster has zero or one endpoint, and no validation error appears.
- **Leaving out `serviceAccount` (item 1).** The machines get no identity, and policies that name identities cannot match them.
- **Creating a Service for the pods (item 10).** That adds them to the registry in another way.
- **Injecting a sidecar proxy into the stand-in pods (item 10).** The task is to add workloads without a sidecar proxy by describing them.
- **Expecting the `WorkloadGroup` to create endpoints (item 3).** Nothing appears until a real machine registers.
- **Expecting a `WorkloadEntry` to create a network path (item 1).** It describes a workload. The address must already be reachable from the pods.
