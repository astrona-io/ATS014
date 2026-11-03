# Solution Walkthrough

The setup has three faults. The `workloadSelector` of the `ServiceEntry` matches no entry, one `WorkloadEntry` has a misspelled label, and the `ServiceEntry` uses `MESH_EXTERNAL` for machines you run yourself. The first two faults show up in the `shuttle` sidecar proxy. The third one shows up only when you read the object.

## Step 1: Read the symptom

Send one request to the host name, and read the last line of the `shuttle` access log. The access log is where the sidecar proxy writes one line per request:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T23:09:39.793Z] "GET /hostname HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 2 - "-" "curl/8.11.1" "afc2e7bb-0170-4bc8-9e1d-89948e4631ab" "freighter.starfleet.mesh:8080" "-" outbound|8080||freighter.starfleet.mesh - 240.240.0.1:8080 10.244.0.6:45400 - default
```

The response flag is `UH` (no healthy upstream), and the upstream address field is `"-"`. The name resolves, and the proxy has the cluster `outbound|8080||freighter.starfleet.mesh`, but the cluster has no endpoint. `istioctl analyze -n starfleet` reports no issues here, because a selector that matches nothing is valid configuration.

## Step 2: Compare the selector with the entries

List the endpoints of the cluster, then show the `ServiceEntry` settings and the entries side by side:

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

The output shows three faults:

- The selector asks for `app: freighters`. No entry carries that label, so the endpoint list is empty.
- `freighter-vm-2` carries `app: freigther`, with two letters swapped. If you fix only the selector, this machine still has no endpoint.
- The location is `MESH_EXTERNAL`. Requests would work with it, but it tells the mesh that these machines are not part of it. They get no identity, and callers never use mTLS (mutual TLS) toward them, even after the real machines run a sidecar proxy.

## Step 3: Fix the ServiceEntry

Write the whole `ServiceEntry` again, with the correct selector and the correct location. Save this as `serviceentry-freighter.yaml`:

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

Requests succeed again, but only `freighter-vm-1` answers. The cluster has one endpoint, because only one entry carries `app: freighter`. If you stopped here, every status code would look fine, and the grader would still fail the task.

The `DestinationRule` with `tls` mode `DISABLE` is what lets this work with `MESH_INTERNAL`. Without it, the `shuttle` proxy would use mTLS toward pods that have no sidecar proxy, and every request would fail.

## Step 4: Fix the label of the second entry

Get the address of the second entry, so you can write the entry again with the same address:

```sh
kubectl get workloadentry freighter-vm-2 -n starfleet -o jsonpath='{.spec.address}{"\n"}'
```

```text
10.244.0.10
```

In the YAML, replace `<FREIGHTER_VM_2>` with that address. Save this as `workloadentry-freighter-vm-2.yaml`:

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

The cluster has two endpoints, and both pods answer. Your split between the two will be different, and so will the addresses in your lab. Send the setup for grading with `astrona submit -c sections/section-070/module-03/labs/lab-02`.

## Mistakes that fail the grader

- **Fixing only the selector.** One machine answers, every status code is `200`, and the grader counts one endpoint instead of two.
- **Changing the selector to `app: freigther` to match the broken entry.** Then `freighter-vm-1` drops out instead. Fix the entry, and keep the selector at `app: freighter`.
- **Leaving `location: MESH_EXTERNAL`.** Requests work, and the grader still fails it: machines you run yourself must be `MESH_INTERNAL`.
- **Deleting the `DestinationRule`.** With `MESH_INTERNAL`, the `shuttle` proxy then uses mTLS toward pods that have no sidecar proxy, and every request fails with `503` and `WRONG_VERSION_NUMBER` in the access log.
- **Creating a Service for the freighter pods, or injecting a sidecar proxy into them.** The task is to add machines outside the mesh with `WorkloadEntry` objects.
- **Changing the address or ServiceAccount of an entry.** They were correct. The address is where the machine is, and the ServiceAccount is its identity.
