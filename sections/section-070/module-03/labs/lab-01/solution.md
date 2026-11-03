# Solution Walkthrough

The task needs four objects: two `WorkloadEntry` objects (one per machine), one `ServiceEntry` (the host name in front of them) and one `WorkloadGroup` (the template for real machines). The field that decides whether the task passes is `location` in the `ServiceEntry`.

## Step 1: See what the mesh knows today

Read the two addresses, list the pods, and send one request by IP address and one by host name. Then count the clusters for the machines in the `tester` sidecar proxy. In Envoy, a cluster is a named destination with a list of endpoints:

```sh
VM1=$(cat /tmp/vm1-ip); VM2=$(cat /tmp/vm2-ip)
echo "vm1=$VM1  vm2=$VM2"
kubectl -n vm-demo get pods -o wide

kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by address: %{http_code}\n" --max-time 10 "http://$VM1:8080/get"
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name:    %{http_code}\n" --max-time 10 "http://legacy.vm-demo.svc:8080/get"
istioctl proxy-config cluster deploy/tester -n vm-demo | grep -c legacy
```

```text
vm1=10.244.0.31  vm2=10.244.0.33
NAME            READY   STATUS    IP
legacy-vm-1     1/1     Running   10.244.0.31
legacy-vm-2     1/1     Running   10.244.0.33
tester          2/2     Running   10.244.0.32
by address: 200
by name:    000
0
```

The output shows three facts. Both machines answer by IP address. The host name does not resolve, so `curl` returns `000`. And the `tester` proxy has zero clusters for the machines: they are not in the service registry, so no policy, telemetry or host name applies to them.

The `READY` column shows `1/1` for the machines and `2/2` for `tester`. The stand-in pods have no sidecar proxy, which is what makes them behave like machines outside the mesh.

## Step 2: Describe both machines

Each machine needs its own `WorkloadEntry`. In the YAML below, replace `<VM1>` with the address that `echo $VM1` prints. Save this as `workloadentry-legacy-vm-1.yaml`:

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

You write the addresses into the entries yourself. That is the practical difference from a pod: Kubernetes records the address of a pod for you, but nobody does that for a machine outside Kubernetes.

The same label `app: legacy-backend` on both entries is what makes them one service in the next step. The field `serviceAccount: legacy-sa` gives each machine the SPIFFE (Secure Production Identity Framework For Everyone) identity `spiffe://cluster.local/ns/vm-demo/sa/legacy-sa`. That is the same identity a pod running as that ServiceAccount would have, and it is why an `AuthorizationPolicy` can name these machines.

The entries alone change nothing you can see yet: there is still no host name, because a `WorkloadEntry` has no host and no service port.

## Step 3: Give the machines one host name

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

Three fields are different from a `ServiceEntry` for somebody else's service, and each one matters:

- **`location: MESH_INTERNAL`.** These are your own workloads. This setting makes the identity count, makes callers use mTLS (mutual TLS) toward them, and lets an `AuthorizationPolicy` name them. `MESH_EXTERNAL` would also give you a working host name, but none of the rest. That is why the grader checks the field: the requests look fine either way.
- **`resolution: STATIC`.** The entries already hold the addresses, so there is nothing to look up. The grader checks this too.
- **`workloadSelector`.** It links the host to the entries by label.

Because the location is `MESH_INTERNAL`, the `tester` proxy would use mTLS toward the machines, and the stand-in pods cannot accept it. The `legacy-plaintext` `DestinationRule` that the lab created sets `tls` mode `DISABLE` for this host, so the requests use plain HTTP. A real virtual machine running `istio-agent` would not need it.

## Step 4: Check the service registry

Send a request by host name, then list the cluster and its endpoints in the `tester` proxy:

```sh
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name: %{http_code}\n" --max-time 10 http://legacy.vm-demo.svc:8080/get
istioctl proxy-config cluster deploy/tester -n vm-demo | grep legacy
istioctl proxy-config endpoints deploy/tester -n vm-demo \
  --cluster "outbound|8080||legacy.vm-demo.svc"
```

```text
by name: 200
legacy.vm-demo.svc                                             8080      -          outbound      EDS              legacy-plaintext.vm-demo
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8080     HEALTHY     OK                outbound|8080||legacy.vm-demo.svc
10.244.0.9:8080     HEALTHY     OK                outbound|8080||legacy.vm-demo.svc
```

The host name works, and the cluster has two endpoints, one per machine, joined by the shared label. The cluster `TYPE` is `EDS` (Endpoint Discovery Service), not `STATIC`: because the `ServiceEntry` selects its endpoints with `workloadSelector`, `istiod` sends the endpoint list to the proxy separately, the same way as for a Kubernetes Service. The last column shows that the `legacy-plaintext` `DestinationRule` applies to this cluster. Load balancing, outlier detection and locality settings now apply to them the same way as to two pods.

If you see only one endpoint, one of the entries has a different label than the selector.

## Step 5: Write the template for real machines

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

Then check the result:

```sh
kubectl -n vm-demo get workloadgroup,workloadentry
```

```text
NAME                                             AGE
workloadgroup.networking.istio.io/legacy         3s
workloadentry.networking.istio.io/legacy-vm-1    4m
workloadentry.networking.istio.io/legacy-vm-2    4m
```

There are still only the two entries you wrote. No third entry appears, and none will. A real virtual machine runs `istio-agent`, the Istio program that starts its sidecar proxy, connects to `istiod` with a ServiceAccount token and registers against the group. The stand-in pods do none of this.

Compare the `template` of the group with the fields of an entry: the same ServiceAccount, the same labels, the same port. On a real machine, `istiod` creates the `WorkloadEntry` from exactly these values, with the address taken from the machine itself. A `WorkloadGroup` relates to `WorkloadEntry` objects the way a Deployment relates to Pods.

Send the setup for grading with `astrona submit -c sections/section-070/module-03/labs/lab-01`.

## Common mistakes

- **`location: MESH_EXTERNAL`.** Requests are routed, but the machines get no identity. This is the most likely way to fail the task while it looks like it works.
- **`resolution: DNS`.** The entries already hold the addresses, so the task asks for `STATIC`, and the grader checks it.
- **Labels that do not match.** The `workloadSelector` and the `labels` of the entries must agree. Otherwise the cluster has zero or one endpoint, and no validation error appears.
- **Leaving out `serviceAccount`.** The machines get no identity, and policies that name identities cannot match them.
- **Creating a Service for the pods.** That adds them to the registry in a different way, and the grader rejects it.
- **Injecting a sidecar proxy into the stand-in pods.** The task is to add workloads without a sidecar proxy by describing them.
- **Expecting the `WorkloadGroup` to create endpoints.** Nothing appears until a real machine registers.
- **Expecting a `WorkloadEntry` to create a network path.** It describes a workload; the address must already be reachable from the pods.
