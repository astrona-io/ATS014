# Wrap-Up: Mission Debrief

Well flown, astronaut. You have brought old ships that fly outside Kubernetes onto the star chart, as members of the fleet. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about three objects that bring machines outside Kubernetes into the mesh: the `WorkloadEntry` (one machine), the `ServiceEntry` with a `workloadSelector` (one name for many machines), and the `WorkloadGroup` (a template machines register against).

**From [`WorkloadEntry`: One Old Ship](./course-01-workloadentry-one-instance.md):**

- A machine the mesh does not know can still be reached by its address. The caller's flight log shows `PassthroughCluster`, and the proxy has no cluster for it.
- A `WorkloadEntry` describes one machine with three fields: `address` (where it is), `labels` (how a `ServiceEntry` finds it) and `serviceAccount` (its identity).
- A `WorkloadEntry` alone gives no name and no cluster. Something must select it.
- `serviceAccount` gives the machine the identity `spiffe://cluster.local/ns/<namespace>/sa/<service-account>`, so `AuthorizationPolicy` and `PeerAuthentication` can name it. The ServiceAccount must exist in the entry's namespace.

**From [`MESH_INTERNAL` And The Selector](./course-02-mesh-internal-and-the-selector.md):**

- A `ServiceEntry` for your own machines uses `location: MESH_INTERNAL`, `resolution: STATIC` and a `workloadSelector` that matches the entries' labels.
- The proxy gets an `EDS` cluster for the host, with the entries' addresses as its endpoints.
- `MESH_INTERNAL` makes the caller start mutual TLS. A machine with no sidecar fails it with `503 UF` and `WRONG_VERSION_NUMBER`. The cluster's `tlsMode-istio` setting shows the handshake is on.
- `MESH_EXTERNAL` makes the signal work, but treats your machine as a stranger: no identity, no handshake.
- For a stand-in with no sidecar, a `DestinationRule` with `tls` mode `DISABLE` lets callers use plain HTTP. A real onboarded machine does not need it.

**From [Two Ships, One Beacon](./course-03-two-ships-one-beacon.md):**

- A second `WorkloadEntry` with the same labels becomes a second endpoint behind the same name, with no change to the `ServiceEntry`.
- A selector that matches no entry gives an empty endpoint list and `503 UH`, and `istioctl analyze` stays quiet.
- The `workloadSelector` also picks pods with matching labels in the same namespace.
- A `ServiceEntry` cannot have both `endpoints` and a `workloadSelector`.

**From [`WorkloadGroup` And Real Onboarding](./course-04-workloadgroup-and-real-onboarding.md):**

- A `WorkloadGroup` is a template: labels, ServiceAccount and ports, but no address. It is to `WorkloadEntry` what a Deployment is to a Pod.
- A real machine with `istio-agent` registers against the group, and `istiod` writes its `WorkloadEntry`. A stand-in without the agent never registers.
- A real machine needs `istio-agent`, a token, the root certificate, a configuration file, a path to `istiod` on port `15012`, and an address the pods can reach.
- `istioctl x workload entry configure` builds the onboarding files from the group. The token in them is a real credential.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Bring The Lost Freighters Back](./labs/lab-02/README.md) | Two Ships, One Beacon | find a selector and a label that match nothing, and make the beacon mesh-internal |
| [Bring Two Old Ships Into The Mesh](./labs/lab-01/README.md) | `WorkloadGroup` And Real Onboarding | bring two machines into the mesh as one service, with identity and a `WorkloadGroup` |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You applied a <code>WorkloadEntry</code> for a machine. Can a pod now call the machine by a name?</summary>

No. A `WorkloadEntry` describes one machine, but it has no host name and no port for callers. A `ServiceEntry` whose `workloadSelector` matches the entry's labels gives it a name and a port.
</details>

<details>
<summary>2. What does the <code>serviceAccount</code> field of a <code>WorkloadEntry</code> give the machine?</summary>

An identity, in the form `spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>`. Policies that name identities, such as `AuthorizationPolicy`, can then name the machine. Without it, the machine is reachable but anonymous.
</details>

<details>
<summary>3. Your machine answers by name with <code>location: MESH_EXTERNAL</code>. Why change it to <code>MESH_INTERNAL</code>?</summary>

`MESH_EXTERNAL` treats the machine as somebody else's service. It routes, but the machine gets no identity and the callers never start mutual TLS. `MESH_INTERNAL` makes it a member of the mesh.
</details>

<details>
<summary>4. After switching to <code>MESH_INTERNAL</code>, every signal fails with <code>503</code> and <code>WRONG_VERSION_NUMBER</code> in the caller's flight log. What is happening?</summary>

The caller's proxy starts mutual TLS, and the machine answers in plain HTTP because it has no sidecar. On a real machine, start `istio-agent`. For a stand-in that never will have one, a `DestinationRule` with `tls` mode `DISABLE` for the host lets callers use plain HTTP.
</details>

<details>
<summary>5. A name from your <code>ServiceEntry</code> answers <code>503</code> with the flag <code>UH</code>, and <code>istioctl analyze</code> is clean. What do you check first?</summary>

The endpoints: `istioctl proxy-config endpoints deploy/<caller> -n <namespace> --cluster "outbound|<port>||<host>"`. An empty list means the `workloadSelector` labels match no `WorkloadEntry`. Compare the two sides letter by letter.
</details>

<details>
<summary>6. You need a third machine behind the same name. What do you create?</summary>

One more `WorkloadEntry` with the same labels, in the same namespace. The `ServiceEntry` stays as it is: its selector picks up the new entry.
</details>

<details>
<summary>7. You apply a <code>WorkloadGroup</code>, but no new <code>WorkloadEntry</code> appears. Is something broken?</summary>

Not necessarily. A `WorkloadGroup` is only a template. Entries appear when a machine running `istio-agent`, with a token and a path to `istiod`, registers against the group.
</details>

<details>
<summary>8. Which <code>resolution</code> do you use when a <code>workloadSelector</code> picks <code>WorkloadEntry</code> objects, and why?</summary>

`STATIC`. The entries already hold the addresses, so nothing needs to be looked up.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-070-03
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-070-03-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

If you built onboarding files with `istioctl x workload entry configure`, delete the `vm-files` folder on your own machine too.

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *A `WorkloadEntry` puts one old ship on the star chart, a `MESH_INTERNAL` `ServiceEntry` makes it one of the fleet, and a `WorkloadGroup` lets the ships chart themselves.*
