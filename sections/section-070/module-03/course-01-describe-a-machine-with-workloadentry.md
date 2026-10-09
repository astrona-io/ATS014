# Describe A Machine Outside Kubernetes With WorkloadEntry

Some workloads never run in Kubernetes: a database on a virtual machine, an old service nobody has moved into a container, a device with a fixed address. Pods in the mesh can often reach such a machine by its IP address, but Istio knows nothing about it. No routing rule, policy or log line can name it. This part shows what the mesh sees today, and then writes the first object that describes the machine to Istio.

## A machine the mesh does not know

Start with the machine as it is. The `freighter-vm-1` pod stands in for a virtual machine: it has no sidecar proxy and no Kubernetes Service. A sidecar proxy is the Envoy container that Istio adds to a pod; all traffic in and out of the pod passes through it. `istiod`, Istio's control plane, builds the configuration for every sidecar proxy from the service registry, the list of hosts and endpoints it knows about.

<!-- astrona:playground:renew -->

List the pods in the `starfleet` namespace, with their IP addresses:

```sh
kubectl get pods -n starfleet -o wide
```

You should see (the `NODE` columns trimmed):

```text
NAME                              READY   STATUS    RESTARTS   AGE   IP
freighter-vm-1-684c9b8695-65dlz   1/1     Running   0          11s   10.244.0.9
freighter-vm-2-745547488b-m5244   1/1     Running   0          11s   10.244.0.10
shuttle-7b5db664c-d27cb           2/2     Running   0          45s   10.244.0.6
```

The `READY` column tells the two kinds of pod apart. The `shuttle` pod shows `2/2`: the application container plus the `istio-proxy` sidecar. The freighter pods show `1/1`: they have no sidecar. Your addresses will be different.

Keep the first freighter's address in a variable, so you do not have to type it:

```sh
FREIGHTER_VM_1=$(kubectl get pod -n starfleet -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}')
echo $FREIGHTER_VM_1
```

```text
10.244.0.9
```

Now send a request from `shuttle` to that address. Then ask the `shuttle` sidecar proxy whether it has a cluster for the freighter. In Envoy, a cluster is a named destination with a list of endpoints (IP address and port pairs) that the proxy can send requests to.

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://$FREIGHTER_VM_1:8080/hostname
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep freighter
```

You should see:

```text
{
  "hostname": "freighter-vm-1-684c9b8695-65dlz"
}
```

The request arrives, but the second command prints nothing. The `shuttle` proxy has no cluster for the freighter. The access log of the proxy says how it handled the request. The access log is where each sidecar proxy writes one line per request:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (trimmed):

```text
[2026-10-08T23:00:46.585Z] "- - -" 0 - - - "-" 87 247 9 - "-" "-" "-" "-" "10.244.0.9:8080" PassthroughCluster ...
```

`PassthroughCluster` is the cluster the proxy uses for an address that is not in the service registry: it forwards the connection without any rules. The `"- - -"` shows that the proxy did not even read the request as HTTP; it handled a raw TCP connection. So the machine has no host name, no policy can point at it, and every caller breaks when its address changes.

## The `WorkloadEntry` object

Istio fixes this with a `WorkloadEntry`. A `WorkloadEntry` describes one workload that does not run in Kubernetes, so `istiod` can add it to the service registry. Kubernetes keeps a pod object for every pod it runs, with its address and labels. Nobody does that for a virtual machine, so you write the `WorkloadEntry` yourself. Three fields matter for most tasks:

| Field | What it does |
| --- | --- |
| `address` | The IP address (or DNS name) of the machine. Pods must already be able to reach it; the object does not create a network path |
| `labels` | Labels that a `ServiceEntry` selects on, the same way a Kubernetes Service selects pods by label |
| `serviceAccount` | The Kubernetes ServiceAccount the machine runs as. It sets the machine's identity in the mesh |

The object has a few more fields, for example `network` for a mesh that spans several networks, `locality` for the machine's region and zone, `weight` and `ports`. Exam tasks normally ask for the three above. One `WorkloadEntry` describes exactly one machine, so three machines of the same service need three entries with the same labels.

Write the entry for the first freighter. In the YAML, replace `<FREIGHTER_VM_1>` with the address that `echo $FREIGHTER_VM_1` printed. Save this as `workloadentry-freighter-vm-1.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: freighter-vm-1
  namespace: starfleet
spec:
  address: <FREIGHTER_VM_1>
  labels:
    app: freighter
  serviceAccount: freighter
```

Apply it:

```sh
kubectl apply -f workloadentry-freighter-vm-1.yaml
```

Then check the result:

```sh
kubectl get workloadentry -n starfleet
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep freighter
```

You should see:

```text
NAME             AGE   ADDRESS
freighter-vm-1   0s    10.244.0.9
```

The entry exists, but the second command still prints nothing. A `WorkloadEntry` describes a machine, but it has no host name and no service port that a caller could use, so `istiod` builds no cluster from it. A `ServiceEntry` with a `workloadSelector` adds the host name and the port. Before that, one field of the entry needs a closer look, because it is what makes the machine a member of the mesh and not only an address.

## What `serviceAccount` gives the machine

Istio gives every workload an identity in one fixed format, called SPIFFE (Secure Production Identity Framework For Everyone). The SPIFFE ID is built from the trust domain, the namespace and the service account:

```text
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>

for this entry:
spiffe://cluster.local/ns/starfleet/sa/freighter
```

This is the same identity that a pod running as the `freighter` ServiceAccount in `starfleet` would have. So every Istio object that names identities can name the machine too:

| Object | What it can do with the identity |
| --- | --- |
| `AuthorizationPolicy` | Allow or deny requests from this identity |
| `PeerAuthentication` | Require mTLS (mutual TLS, where both sides present a certificate) from it |
| Telemetry and access logs | Show the identity instead of a bare IP address |

If you leave `serviceAccount` out, the machine can still get a host name and routing, but it has no identity. A policy that names identities can never match it.

The ServiceAccount must exist in the same namespace as the `WorkloadEntry`, because the namespace is part of the identity. The playground already has it:

```sh
kubectl get serviceaccount freighter -n starfleet
```

```text
NAME        AGE
freighter   49s
```

On a real virtual machine, the machine also proves this identity. It runs `istio-agent`, the Istio program that starts the machine's sidecar proxy. The agent sends a ServiceAccount token to `istiod` and gets a certificate for the identity back. The stand-in pod has no sidecar, so here the identity is only declared, not proved.

You can now describe one machine to Istio. The `address` field makes the machine reachable, `labels` make it selectable, and `serviceAccount` gives it an identity that policies can name. The open question is how a caller reaches the machine by a host name, and that needs a second object.

## Common pitfalls

> [!WARNING]
> - **Expecting a `WorkloadEntry` alone to be callable by name.** It describes one machine. The proxy has no cluster for it until a `ServiceEntry` selects it.
> - **Leaving `serviceAccount` out.** The machine gets no identity, so no `AuthorizationPolicy` or `PeerAuthentication` can name it.
> - **Naming a ServiceAccount from another namespace.** The identity includes the namespace of the `WorkloadEntry`. Create the ServiceAccount there.
> - **Treating the entry as a network path.** Pods must already be able to reach the address. The `WorkloadEntry` only describes it.
