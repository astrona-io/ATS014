# Connecting In-Mesh Workloads To External Workloads And Services

The edge of the mesh is not the edge of your application. Real systems send requests to payment APIs, object stores and partner endpoints outside the cluster. They also talk to databases and older services that run on virtual machines, not in Kubernetes.

This section is about both kinds of "outside". The first two modules deal with services somebody else runs. You add them to the service registry so the mesh can apply rules to the requests, and you move the TLS (Transport Layer Security) connection to the sidecar proxy so the proxy can read them. The last module deals with a workload **you** run outside Kubernetes. It needs more than routing. It needs an identity, so one set of rules covers pods and virtual machines alike.

The order matters. `ServiceEntry` is the object all three modules use, so it comes first; TLS origination is a use of it; `WorkloadEntry` is the same object with `MESH_INTERNAL` and a selector.

**Curriculum item covered:** Connecting In-Mesh Workloads to External Workloads and Services

---

## What You Will Master

- `meshConfig.outboundTrafficPolicy.mode`: `ALLOW_ANY` as the permissive default, `REGISTRY_ONLY` as deny-by-default, and the per-namespace `Sidecar` override.
- Recognising the sidecar's 502 as "not in the registry" rather than a network fault, against the other failure signatures.
- `ServiceEntry` fields — `hosts`, `ports` with an explicit `protocol`, `location`, `resolution` — and what each decides.
- Why a declared `protocol: HTTP` is what unlocks timeouts, retries and routing for an external host.
- A registered external host behaving like any other host for `VirtualService` and `DestinationRule`.
- `exportTo` scope, and how a `Sidecar` resource can hide a valid `ServiceEntry` from one namespace.
- Exactly what a sidecar can and cannot see in an application-originated TLS stream — and that TCP connection pools still work on one.
- TLS origination as three cooperating objects, with `tls.mode: SIMPLE` and `sni` under `portLevelSettings` for the HTTPS port.
- Proving origination from the destination's own view rather than from a status code.
- What `MUTUAL` changes, where `credentialName` is read from, and why that argues for one shared egress gateway that holds the certificate.
- `WorkloadEntry` for one non-Kubernetes instance: `address`, `labels`, `serviceAccount` and the SPIFFE identity it yields.
- `MESH_INTERNAL` versus `MESH_EXTERNAL` — routing versus routing plus identity, mTLS (mutual TLS, where both sides prove who they are) and policy coverage.
- `WorkloadGroup` as the auto-registration template, and the five things a real virtual machine needs before it can register.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary. The capstone lab at the end uses everything in the section at once.

### Control External Access With ServiceEntry

5 parts and 2 labs:

1. Block Unknown Hosts With REGISTRY_ONLY
2. Add An External Host With ServiceEntry
3. Apply Timeouts And Connection Pools To An External Host
   - Lab: Allow One External Host Under REGISTRY_ONLY Lab
4. Find A ServiceEntry Hidden By A Sidecar
5. Limit A ServiceEntry With exportTo
   - Lab: Fix A Hidden ServiceEntry And Its Port Protocol Lab
6. Summary

### TLS Origination For External Services

4 parts and 2 labs:

1. Why The Proxy Cannot Read HTTPS Calls
2. Originate TLS With Three Istio Objects
3. Troubleshoot Top-Level TLS And Double Encryption
   - Lab: Fix A Broken TLS Origination Lab
4. Verify TLS Origination And Configure Mutual TLS
   - Lab: Originate TLS To A TLS-Only External Service Lab
5. Summary

### Add External Workloads With WorkloadEntry

4 parts and 2 labs:

1. Describe A Machine Outside Kubernetes With WorkloadEntry
2. Name The Machines With A MESH_INTERNAL ServiceEntry
3. Put Several Machines Behind One Host With workloadSelector
   - Lab: Fix A ServiceEntry Selector And WorkloadEntry Labels Lab
4. Register Virtual Machines With WorkloadGroup
   - Lab: Add Two Virtual Machines To The Mesh With WorkloadEntry Lab
5. Summary

### Capstone

The section ends with a capstone lab that uses everything in it: **Register An External API And A Virtual Machine In A REGISTRY_ONLY Mesh Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->
