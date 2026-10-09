# `WorkloadGroup` And Real Onboarding

Astronaut, writing one `WorkloadEntry` per machine is like charting every ship by hand. It works for two old freighters. It does not work for a squadron where machines start and stop every hour. A `WorkloadGroup` lets each machine add itself to the star chart. This part shows the object, what a real virtual machine needs to use it, and exactly where your playground stops.

The commands below need the `freighter-vm-1` and `freighter-vm-2` `WorkloadEntry` objects applied in your playground, each with the label `app: freighter` and the ServiceAccount `freighter`.

## The trouble with hand-written entries

Two failures follow from a person being the one who charts every machine:

- **A new machine has an address nobody wrote down.** Until someone writes its `WorkloadEntry`, the mesh cannot send it a single signal, even though it is up and ready.
- **A removed machine leaves an old entry behind.** The proxy keeps an endpoint that no longer exists, and callers hit failures until someone notices.

Neither is a mistake in the YAML. Both come from charting by hand.

## `WorkloadGroup`: a template for many machines

A **`WorkloadGroup`** describes what every machine of one service **looks like**: its labels, its ServiceAccount and its ports, and optionally a health check. It names no address. A real virtual machine running `istio-agent` radios mission control when it starts and says "I belong to this group". Mission control (`istiod`) then writes the `WorkloadEntry` for it, with the machine's own address, and removes it again when the machine disconnects.

The three object names blur together, so compare them with the Kubernetes objects you know:

| For machines outside Kubernetes | Is to | As, in Kubernetes | Is to |
| --- | --- | --- | --- |
| `WorkloadGroup` | `WorkloadEntry` | Deployment | Pod |
| `ServiceEntry` with a `workloadSelector` | the entries it selects | Service | the pods it selects |

The first row is "a template that makes instances". The second is "a name and ports in front of whatever matches". So a fully automatic setup has only **two** hand-written objects, the `WorkloadGroup` and the `ServiceEntry`, and no `WorkloadEntry` written by hand at all.

<!-- astrona:playground:renew -->

### Write the template next to the entries

Write a group whose template matches the two entries you wrote by hand. Save this as `workloadgroup-freighter.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: freighter
  namespace: starfleet
spec:
  metadata:
    labels:
      app: freighter
  template:
    serviceAccount: freighter
    ports:
      http: 8080
```

Apply it:

```sh
kubectl apply -f workloadgroup-freighter.yaml
```

Then check the result:

```sh
kubectl get workloadgroup,workloadentry -n starfleet
```

You should see:

```text
NAME                                          AGE
workloadgroup.networking.istio.io/freighter   0s

NAME                                               AGE    ADDRESS
workloadentry.networking.istio.io/freighter-vm-1   109s   10.244.0.9
workloadentry.networking.istio.io/freighter-vm-2   33s    10.244.0.10
```

One group, and still only the two entries **you** wrote. No new entry appeared, and none will: your stand-ins do not run `istio-agent`, so nothing can register against the group. Compare the group with the entries anyway. Same labels, same ServiceAccount, same port. That is exactly what registration would fill in, with the address taken from the machine itself.

## What a real virtual machine needs

Registration is not only configuration. Before a machine can register, it needs all of this:

| What it needs | Why |
| --- | --- |
| `istio-agent` installed and running | It starts the machine's sidecar, connects to `istiod` and registers |
| A **token** for the group's ServiceAccount | It proves the machine may use that identity |
| The mesh's **root certificate** | So the machine can trust mission control |
| A configuration file (`cluster.env`, `mesh.yaml`) | Trust domain, network, group and the address of `istiod` |
| A network path to `istiod` on port `15012` | The channel mission control sends its orders over |
| An address the pods can reach | Otherwise nobody can signal the machine once it is registered |

You do not write the token, certificate and configuration by hand. `istioctl` builds them from the `WorkloadGroup`, ready to copy onto the machine.

### Build the files a real machine would get

Ask `istioctl` for the onboarding files of the `freighter` group, written to a local folder called `vm-files`:

```sh
istioctl x workload entry configure -f workloadgroup-freighter.yaml -o vm-files --clusterID Kubernetes --autoregister
```

You should see:

```text
Warning: a security token for namespace "starfleet" and service account "freighter" has been generated and stored at "vm-files/istio-token"
2026-10-08T23:02:45.199096Z	warn	Could not auto-detect IP for istiod.istio-system.svc/istio-system. Use --ingressIP to manually specify the Gateway address to reach istiod from the VM.
Configuration generation into directory vm-files was successful
```

Then look at what it wrote, and at the part of `cluster.env` that comes from your group:

```sh
ls vm-files
grep -E "AUTO_REGISTER|SERVICE_ACCOUNT|METAJSON_LABELS|INBOUND_PORTS" vm-files/cluster.env
```

```text
cluster.env
hosts
istio-token
mesh.yaml
root-cert.pem
ISTIO_INBOUND_PORTS='8080'
ISTIO_METAJSON_LABELS='{"app":"freighter","service.istio.io/canonical-name":"freighter","service.istio.io/canonical-revision":"latest"}'
ISTIO_META_AUTO_REGISTER_GROUP='freighter'
SERVICE_ACCOUNT='freighter'
```

Every value from your `WorkloadGroup` is there: the port, the label, the ServiceAccount, and `ISTIO_META_AUTO_REGISTER_GROUP`, which tells the agent which group to register against. The token and the root certificate are the machine's papers. The warning says that `istioctl` could not find an address for `istiod` that a machine outside the cluster could reach. A real setup exposes `istiod` through a gateway and passes that address with `--ingressIP`. Your playground has no such gateway, which is one more thing a stand-in cannot show.

## What this playground cannot show

It is better to say this plainly than to pretend. The stand-in is a pod without a sidecar. Everything about naming, selecting and routing works on it exactly as on a real machine. Three things do not:

- **Registering itself.** It runs no `istio-agent`, has no token and never talks to `istiod`. Your `WorkloadGroup` is valid, and no entry will ever come from it here.
- **Proving its identity.** The `serviceAccount` on your entries is a declaration. A real machine shows its token and gets a certificate.
- **The secret handshake.** `MESH_INTERNAL` makes callers start mutual TLS, which the stand-in cannot answer. That is why your playground needs the `tls` `DISABLE` `DestinationRule`, and a real onboarded machine does not.

Clean up the files on your own machine when you are done. The token in them is a real credential for the `freighter` identity:

```sh
rm -rf vm-files
```

> *A `WorkloadGroup` is to a `WorkloadEntry` what a Deployment is to a Pod. Like a Deployment, it needs something on the other end that actually starts: here, `istio-agent` on the machine.*

## Common pitfalls

> [!WARNING]
> - **Mixing up `WorkloadGroup` and `WorkloadEntry`.** The group is the template; the entry is one concrete machine with an address.
> - **Expecting a `WorkloadGroup` alone to create endpoints.** Nothing appears until a machine with `istio-agent` registers against it.
> - **A template that does not match the `ServiceEntry`.** Registered entries get the group's labels. If the `workloadSelector` does not match them, the name has no endpoints.
> - **Forgetting the ServiceAccount.** The template's `serviceAccount` must exist in the group's namespace, and the token is made for it.
> - **Forgetting the network path.** The machine must reach `istiod` on port `15012`, and the pods must reach the machine.
> - **Leaving onboarding files lying around.** `istio-token` is a working credential. Treat it like a password.

## Your mission: Bring Two Old Ships Into The Mesh

You can now describe machines with `WorkloadEntry`, give them a name with a `MESH_INTERNAL` `ServiceEntry`, and write the `WorkloadGroup` a real fleet registers against. Now prove it in a graded mission: bring two stand-in machines into the mesh as one service, from nothing.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-03
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-03/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-070-03
astrona start ats-014-playground-070-03
```
