# Mesh Foundations

Before you configure a mesh, it helps to know what is already running. A namespace labelled for injection gets a proxy in every pod, traffic redirected into it, and a full set of configuration pushed to it — all before you write a single Istio object.

This section is one module covering exactly that: what injection adds, how `istiod` programs the proxies, and the handful of commands that tell you what a proxy currently holds. It writes no Istio configuration at all.

**Curriculum item covered:** none directly — this is prerequisite material for the whole Traffic Management domain.

---

## What You Will Master

- What sidecar injection adds to a pod, and why labelling a namespace does not change pods that already exist.
- How `iptables` rules put a pod's own traffic through the proxy on ports `15001` and `15006` without the application knowing.
- Why every in-mesh request is logged twice, and what an uninjected caller loses.
- What the service registry is built from, and how `istiod` turns it into Envoy configuration.
- LDS, RDS, CDS and EDS: what each carries and why a push needs no restart.
- The listener → route → cluster → endpoint chain, and how to read each layer with `istioctl proxy-config`.
- Reading an Envoy cluster name: direction, port, subset and host.
- The diagnostic ladder — `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, the access log — and what each one cannot see.
- Access-log response flags, and why `NR` and `UH` point at opposite halves of a configuration.

---

## The Learning Path

### 1. How A Request Moves Through The Mesh
*   **Module Reader:** **[How A Request Moves Through The Mesh](./module-01/course.md)**
    1. [The Sidecar And The Data Path](./module-01/course-01-the-sidecar-and-the-data-path.md)
    2. [How The Proxy Gets Its Configuration](./module-01/course-02-how-the-proxy-gets-its-configuration.md)
    3. [The Diagnostic Toolkit](./module-01/course-03-the-diagnostic-toolkit.md)
*   **Hands-on Playground:** `sections/section-000/module-01/playground` — a kind cluster with Istio installed, one injected namespace holding a client and an API, and one uninjected namespace for contrast. No Istio traffic configuration at all.
    ```bash
    astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-000/module-01/playground
    ```
*   **Practice Lab Sandbox:** **`sections/section-000/module-01/labs/lab-01`**
*   **Lab Run Command:**
    ```bash
    astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-01
    ```
*   **Hands-on Objective:** Find the two workloads that are running perfectly and are nevertheless outside the mesh — one namespace that was never labelled, one pod template that opted out — and bring both in without replacing them. Nothing in `kubectl get` reports either fault.

---

This section has no capstone: it teaches how to look at a mesh, and everything in it is exercised by every graded lab that follows. Its own lab is deliberately diagnostic — the fix is two commands, and finding what to fix is the whole exercise.

The playground is ungraded: it spins up, prepares the environment, and waits. There is no task and no `astrona submit`. Tear it down with `astrona destroy ats-014-playground-000-01` when you are finished.
