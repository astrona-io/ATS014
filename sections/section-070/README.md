# Connecting In-Mesh Workloads To External Workloads And Services

Astronaut, your solar system does not fly alone. The edge of the mesh is not the edge of your application. Real systems send signals to payment APIs, object stores and partner endpoints: planets in other solar systems. They also talk to databases and legacy services that were never going to be containerised: old ships that fly outside the fleet's signal network.

This section is about both kinds of "outside". The first two modules deal with services somebody else runs. You add them to the star chart (the service registry) so the mesh can govern the signals, and you move the TLS boundary so the communications officer can actually read them. The last module deals with a workload **you** run that is not in Kubernetes. It needs more than routing. It needs an identity, so one set of rules covers spaceships (pods) and old machines alike.

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

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Control External Access With ServiceEntry](module-01/course.md)

4 parts and 2 missions:

1. [The Outbound Traffic Policy](module-01/course-01-the-outbound-traffic-policy.md)
2. [The `ServiceEntry` Object](module-01/course-02-the-serviceentry-object.md)
3. [A Registered Host Is An Ordinary Host](module-01/course-03-a-registered-host-is-an-ordinary-host.md)
   - Mission: [Open Exactly One Route Out Lab](module-01/labs/lab-01/question.md)
4. [When A Correct ServiceEntry Is Refused](module-01/course-04-when-a-correct-serviceentry-is-refused.md)
   - Mission: [Reach The Hidden Relay Lab](module-01/labs/lab-02/question.md)
5. [Wrap-Up: Mission Debrief](module-01/course-05-wrap-up.md)

### [TLS Origination For External Services](module-02/course.md)

4 parts and 2 missions:

1. [Why HTTPS Is Opaque](module-02/course-01-why-https-is-opaque.md)
2. [The Three Objects](module-02/course-02-the-three-objects.md)
3. [Two Ways To Break It](module-02/course-03-two-ways-to-break-it.md)
   - Mission: [Repair The Sealed Channel Lab](module-02/labs/lab-02/question.md)
4. [Proving It, And Mutual TLS](module-02/course-04-proving-it-and-mutual-tls.md)
   - Mission: [Seal Signals To A Secure Planet Lab](module-02/labs/lab-01/question.md)
5. [Wrap-Up: Mission Debrief](module-02/course-05-wrap-up.md)

### [Add External Workloads With WorkloadEntry](module-03/course.md)

4 parts and 2 missions:

1. [`WorkloadEntry`: One Old Ship](module-03/course-01-workloadentry-one-instance.md)
2. [`MESH_INTERNAL` And The Selector](module-03/course-02-mesh-internal-and-the-selector.md)
3. [Two Ships, One Beacon](module-03/course-03-two-ships-one-beacon.md)
   - Mission: [Bring The Lost Freighters Back Lab](module-03/labs/lab-02/question.md)
4. [`WorkloadGroup` And Real Onboarding](module-03/course-04-workloadgroup-and-real-onboarding.md)
   - Mission: [Bring Two Old Ships Into The Mesh Lab](module-03/labs/lab-01/question.md)
5. [Wrap-Up: Mission Debrief](module-03/course-05-wrap-up.md)

### Capstone

Your final mission for this section: **[A Deny-By-Default Integration Layer Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
