# `WorkloadEntry`: One Old Ship

Astronaut, before you add a ship to the star chart, look at how the fleet sees it today. Then write one object that describes one machine. It has three fields, and the third one is what makes this more than a name in a phone book.

## Reachable, but anonymous

The old freighter `freighter-vm-1` has an address and answers signals. Mission control knows nothing about it. That is the starting point for every machine outside Kubernetes.

<!-- astrona:playground:renew -->

### Find the freighter's address

List the ships on the planet:

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

Look at the `READY` column. The shuttle shows `2/2`: its app plus its communications officer (the `istio-proxy` sidecar). The freighters show `1/1`: no officer on board. Your addresses will be different.

Keep the first freighter's address in a variable, so you do not have to type it:

```sh
FREIGHTER_VM_1=$(kubectl get pod -n starfleet -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}')
echo $FREIGHTER_VM_1
```

```text
10.244.0.9
```

### Signal the freighter by its address

Send a signal from the shuttle to that address, and ask the shuttle's proxy whether it knows the freighter:

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

The signal arrives, but the second command prints nothing. The shuttle's proxy has no cluster (its list of known destinations) for the freighter. Now read the last line of the shuttle's flight log:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (trimmed):

```text
[2026-10-08T23:00:46.585Z] "- - -" 0 - - - "-" 87 247 9 - "-" "-" "-" "-" "10.244.0.9:8080" PassthroughCluster ...
```

`PassthroughCluster` means "an address I do not know, let it through". The proxy did not even read the signal as HTTP: `"- - -"` is how a raw connection looks in the log. So there is no name to call the freighter by, no policy can point at it, and if its address changes, every caller breaks.

## The `WorkloadEntry` object

A **`WorkloadEntry`** is a hand-written record for one machine that never launched from your fleet. Think of it as a pod record you type yourself: Kubernetes writes one for every pod, but nobody writes one for a virtual machine. It has three fields that matter:

| Field | Its job |
| --- | --- |
| `address` | Where the machine is. It must already be reachable from the pods. The object describes a machine; it does not build a network path to it |
| `labels` | How a `ServiceEntry` will find it, the same way a Service finds pods by their labels |
| `serviceAccount` | The identity the machine runs as. Without it, the machine has no crew papers |

There are a few more fields, for example `network` for a mesh across several networks, `locality` for where the machine sits, `weight` and `ports`. The three above are what a task normally asks for.

**One `WorkloadEntry` describes one machine.** Three machines of the same service need three entries with the same labels.

### Write the first entry

Write the record for the first freighter. Replace `<FREIGHTER_VM_1>` with the address you got from `echo $FREIGHTER_VM_1`. Save this as `workloadentry-freighter-vm-1.yaml`:

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

The entry exists, and the shuttle's proxy still has no cluster for the freighter: the second command prints nothing again. A `WorkloadEntry` describes one machine, but it has no name and no port that a caller could use. A `ServiceEntry` with a `workloadSelector` adds those, and it is the next step on the way.

## What `serviceAccount` gives the machine

The `serviceAccount` field is what turns the freighter from "an address the mesh can route to" into "a member the mesh can govern". Istio gives every workload an identity in one fixed format, called SPIFFE (Secure Production Identity Framework For Everyone). It is the name printed on the crew papers:

```text
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>

for this entry:
spiffe://cluster.local/ns/starfleet/sa/freighter
```

That is exactly the identity a pod running as the `freighter` ServiceAccount in `starfleet` would have. So every rule that names identities can name the freighter too:

| Object | What it can do with the identity |
| --- | --- |
| `AuthorizationPolicy` | allow or deny signals from this identity |
| `PeerAuthentication` | demand the secret handshake (mutual TLS) from it |
| Telemetry and access logs | show the identity instead of a bare address |

Leave `serviceAccount` out and the machine still gets a name and routing, but no identity. A policy that names identities can never match it.

The ServiceAccount must exist in the **same namespace** as the `WorkloadEntry`, because the namespace is part of the identity. Your playground already has it:

```sh
kubectl get serviceaccount freighter -n starfleet
```

```text
NAME        AGE
freighter   49s
```

On a **real** virtual machine, the identity is not only written down: the machine proves it. Its `istio-agent` shows a token when it starts and gets a certificate from mission control. Your stand-in cannot do that, because it has no sidecar. Here, the identity is a declaration only.

> *`address` makes the machine reachable, `labels` make it selectable, and `serviceAccount` makes it governable.*

## Common pitfalls

> [!WARNING]
> - **Expecting a `WorkloadEntry` alone to be callable by name.** It describes one machine. The proxy has no cluster for it until a `ServiceEntry` selects it.
> - **Leaving `serviceAccount` out.** The machine gets no identity, so no `AuthorizationPolicy` or `PeerAuthentication` can name it.
> - **Naming a ServiceAccount from another namespace.** The identity includes the namespace of the `WorkloadEntry`. Create the ServiceAccount there.
> - **Treating the entry as a network path.** The address must already be reachable from the pods. The `WorkloadEntry` only describes it.
