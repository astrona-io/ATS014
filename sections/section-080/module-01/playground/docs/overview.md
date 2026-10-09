# Overview: Route External Traffic Through An Egress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, an egress gateway and the shuttle, and
then waits. There is no task, no `astrona submit` and no pass or fail. Explore,
break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod`, and an
  **egress gateway**, the solar system's departure gate: Helm release
  `istio-egress` in the namespace `istio-egress`, pods labelled
  `istio: egress`, Service type `ClusterIP` with ports `80` and `443`. It is
  running and carries no traffic.
- The mesh at its **`ALLOW_ANY`** default.
- Mesh-wide **access logs**, so the shuttle's sidecar **and** the egress
  gateway each write one line per signal into their flight log.
- Namespace **`starfleet`** (the planet you work on), labelled
  `istio-injection=enabled`, with **`shuttle`**, your client pod inside the
  mesh. You send every test signal from it with the `curl` command.
- **No `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`.**

### Outbound internet

This playground calls `https://httpbin.org` and `https://www.google.com`.
Without outbound internet access you see network failures, not mesh
decisions. Run a plain `curl https://httpbin.org/get` on your own machine
first.

## Helpers

Paste these once in each new terminal. The first sends one signal from the
shuttle (by default to `https://httpbin.org/get`). The other two print the
newest line of each flight log: the shuttle's sidecar, and the egress gateway.

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

## Things to try

Each idea below uses the files you made while reading the module. The
module's parts show the full YAML for every step.

- Chart `httpbin.org` with a `ServiceEntry` only, and call it. `log_shuttle`
  ends at an internet address, and the gate logged nothing.
- Apply the `Gateway` and the `DestinationRule`, then run
  `istioctl proxy-config listener deploy/istio-egress -n istio-egress`. Still
  no listener on `443`: it appears only with the `VirtualService`.
- Apply the two-stage `VirtualService`. Now hop 1 ends at the gate's pod, and
  only hop 2 reaches the internet.
- Remove `mesh` from the top-level `gateways`. `200`, straight out, and
  `istioctl analyze` stays quiet.
- Remove hop 2, or put the gate's own name in the `Gateway`'s
  `servers[].hosts`. The shuttle logs `UF,URX` with `Connection_refused`.
- Delete the `DestinationRule` while the `VirtualService` still names its
  subset. The shuttle logs `NC`.
- Add `sourceLabels` to hop 1, then label the shuttle's pod template with
  `egress-allowed: "true"` and watch it switch from direct to the gate.
- Try the exam-style task in [`practice.md`](practice.md).

## Start over without a new cluster

```sh
kubectl delete virtualservice,destinationrule,serviceentry,gateways.networking.istio.io --all -n starfleet
```

## When you're done

```sh
astrona destroy ats-014-playground-080-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
