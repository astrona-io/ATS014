# Section 070: Connecting In-Mesh Workloads To External Workloads And Services

The mesh boundary is not the same as the application boundary. Real systems call payment APIs, object stores and partner endpoints, and they talk to databases and legacy services that were never going to be containerised.

This section is about both kinds of "outside". Modules 1 and 2 deal with services somebody else runs: registering them so the mesh can govern the traffic, and moving the TLS boundary so it can actually see it. Module 3 deals with a workload **you** run that is not in Kubernetes, which needs more than routing — it needs an identity, so one policy model covers pods and machines alike.

The order matters. `ServiceEntry` is the object all three modules use, so it comes first; TLS origination is a use of it; `WorkloadEntry` is the same object with `MESH_INTERNAL` and a selector. Section 080 then moves the egress work off the sidecars and onto a dedicated gateway.

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
- What `MUTUAL` changes, where `credentialName` is read from, and why that argues for the egress gateway in section 080.
- `WorkloadEntry` for one non-Kubernetes instance: `address`, `labels`, `serviceAccount` and the SPIFFE identity it yields.
- `MESH_INTERNAL` versus `MESH_EXTERNAL` — routing versus routing plus identity, mTLS and policy coverage.
- `WorkloadGroup` as the auto-registration template, and the five things a real VM needs before it can register.

---

## The Learning Path

### 1. Control External Access With ServiceEntry
*   **Module Reader:** **[Module 1: Control External Access With ServiceEntry](./module-01/course.md)**
    1. [The Outbound Traffic Policy](./module-01/course-01-the-outbound-traffic-policy.md)
    2. [The `ServiceEntry` Object](./module-01/course-02-the-serviceentry-object.md)
    3. [A Registered Host Is An Ordinary Host](./module-01/course-03-a-registered-host-is-an-ordinary-host.md)
*   **Hands-on Playground:** `sections/section-070/module-01/playground` — namespace `egress-demo` with a client pod, the mesh at its `ALLOW_ANY` default and no `ServiceEntry`.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-070/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** On a deny-by-default mesh, register exactly one endpoint — with the right `location`, `resolution` and `exportTo` — prove a second is still refused, and put a timeout on the one you allowed.

### 2. TLS Origination For External Services
*   **Module Reader:** **[Module 2: TLS Origination For External Services](./module-02/course.md)**
    1. [Why HTTPS Is Opaque](./module-02/course-01-why-https-is-opaque.md)
    2. [The Three Objects](./module-02/course-02-the-three-objects.md)
    3. [Proving It, And Mutual TLS](./module-02/course-03-proving-it-and-mutual-tls.md)
*   **Hands-on Playground:** `sections/section-070/module-02/playground` — namespace `tlsorig-demo` with a client pod and no Istio configuration.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-02/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-070/module-02/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
    ```
*   **Hands-on Objective:** Reach a TLS-only endpoint over plain `http://`, with the endpoint itself reporting the scheme it was reached over — so there is no guessing whether the sidecar did the handshake.

### 3. Add External Workloads With WorkloadEntry
*   **Module Reader:** **[Module 3: Add External Workloads With WorkloadEntry](./module-03/course.md)**
    1. [`WorkloadEntry`: One Instance](./module-03/course-01-workloadentry-one-instance.md)
    2. [`MESH_INTERNAL` And The Selector](./module-03/course-02-mesh-internal-and-the-selector.md)
    3. [`WorkloadGroup` And Real Onboarding](./module-03/course-03-workloadgroup-and-real-onboarding.md)
*   **Hands-on Playground:** `sections/section-070/module-03/playground` — namespace `vm-demo` with a client pod and a deliberately uninjected `legacy-backend` standing in for a VM. See its `docs/overview.md` for what the stand-in cannot show.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-070/module-03/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-070/module-03/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-01
    ```
*   **Hands-on Objective:** Give two machines outside Kubernetes a hostname, a mesh identity and two endpoints under one service — then write the `WorkloadGroup` a real fleet would register against.

### 4. Section Capstone Challenge
*   **Comprehensive Challenge:** **`sections/section-070/capstone/labs/lab-01` (A Deny-By-Default Integration Layer)**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/capstone/labs/lab-01
    ```
*   **Hands-on Objective:** Three outcomes on a closed mesh at once — a partner's TLS-only API reached over plain HTTP, one of your own machines brought in with identity, and a third endpoint left firmly refused. Two `ServiceEntry` objects, opposite `location` values.

---

The module playgrounds for modules 1 and 2 reach real hosts on the internet; without outbound access you will see network errors rather than mesh behaviour. **Every graded lab and the capstone in this section run entirely offline** — their "external" endpoints are pods deliberately kept out of the mesh registry.

Each playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear one down with `astrona destroy <name>` when you are finished — the name is printed in each module's playground callout.
