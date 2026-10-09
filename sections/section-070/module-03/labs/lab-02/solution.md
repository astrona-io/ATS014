# Solution Walkthrough

Three faults, astronaut: a selector that matches nothing, an entry with a misspelled label, and a location that treats your own freighters as strangers. The first two show up in the shuttle's proxy. The third does not show up anywhere until you read the object.

## Step 1: Read the symptom

Send one signal to the name, and read the shuttle's flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T23:09:39.793Z] "GET /hostname HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 2 - "-" "curl/8.11.1" "afc2e7bb-0170-4bc8-9e1d-89948e4631ab" "freighter.starfleet.mesh:8080" "-" outbound|8080||freighter.starfleet.mesh - 240.240.0.1:8080 10.244.0.6:45400 - default
```

The flag is `UH` (no healthy upstream), and the address field is `"-"`. The name resolves and the proxy has a cluster, `outbound|8080||freighter.starfleet.mesh`, but there is no ship behind it. `istioctl analyze -n starfleet` reports no issues, so do not expect help there.

## Step 2: Compare the selector with the entries

List the endpoints, then put the `ServiceEntry` and the entries side by side:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
kubectl get serviceentry freighter -n starfleet -o jsonpath='{.spec.location} {.spec.resolution} {.spec.workloadSelector.labels}{"\n"}'
kubectl get workloadentry -n starfleet -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,LABELS:.spec.labels,SERVICEACCOUNT:.spec.serviceAccount
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
MESH_EXTERNAL STATIC {"app":"freighters"}
NAME             ADDRESS       LABELS               SERVICEACCOUNT
freighter-vm-1   10.244.0.9    map[app:freighter]   freighter
freighter-vm-2   10.244.0.10   map[app:freigther]   freighter
```

Three findings:

- The selector asks for `app: freighters`. No entry carries that label, so the endpoint list is empty.
- `freighter-vm-2` carries `app: freigther`, with two letters swapped. Fixing the selector alone would leave this freighter out.
- The location is `MESH_EXTERNAL`. Signals would work with it, but it tells the mesh these machines are strangers: no identity, and no mutual TLS once the real machines get a sidecar.

## Step 3: Fix the ServiceEntry

Write the whole `ServiceEntry` again, with the right selector and the right location. Save this as `serviceentry-freighter.yaml`:

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

Then check the result:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname | grep -o 'freighter-vm-[0-9]'
done | sort | uniq -c
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.9:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
  10 freighter-vm-1
```

Signals arrive again, but only `freighter-vm-1` answers. One endpoint, because only one entry carries `app: freighter`. If you stopped here, the status codes would all look fine.

## Step 4: Fix the second entry's label

Get the second freighter's address, so you can write the entry again with the same address:

```sh
kubectl get workloadentry freighter-vm-2 -n starfleet -o jsonpath='{.spec.address}{"\n"}'
```

```text
10.244.0.10
```

Replace `<FREIGHTER_VM_2>` with that address. Save this as `workloadentry-freighter-vm-2.yaml`:

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

Then check the result:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname | grep -o 'freighter-vm-[0-9]'
done | sort | uniq -c
```

```text
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
10.244.0.9:8080      HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
   5 freighter-vm-1
   5 freighter-vm-2
```

Two endpoints, and both freighters answer. Your split between the two will be different. The addresses in your lab will be different too.

## Mistakes that fail the grader

- **Fixing only the selector.** One freighter answers, every status code is `200`, and the grader counts one endpoint instead of two.
- **Changing the selector to `app: freigther` to match the broken entry.** Then `freighter-vm-1` drops out instead. Fix the entry, and keep the selector at `app: freighter`.
- **Leaving `location: MESH_EXTERNAL`.** Everything works, and the grader still fails it: your own machines must be `MESH_INTERNAL`.
- **Deleting the `DestinationRule`.** With `MESH_INTERNAL`, the shuttle's proxy then starts mutual TLS with machines that have no sidecar, and every signal fails with `503` and `WRONG_VERSION_NUMBER` in the flight log.
- **Creating a Service for the freighter pods, or injecting a sidecar into them.** The task is to bring machines outside the mesh in with `WorkloadEntry`.
- **Changing an entry's address or ServiceAccount.** They were correct. The address is where the machine is, and the ServiceAccount is its identity.
