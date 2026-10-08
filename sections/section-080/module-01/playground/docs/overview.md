# Overview: Route External Traffic Through An Egress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, installs Istio, an egress gateway and a few test apps, and then waits. There is no task, no `astrona submit`, and no pass/fail. Explore, break things, `astrona destroy`, start over.

Welcome aboard, astronaut. Think of your cluster as a solar system and each namespace as a planet. Each pod is a spaceship, and its sidecar is the communications officer that every signal goes through. The egress gateway is the solar system's departure gate: one checked exit for signals leaving it. In this playground you make outgoing signals actually use that gate.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it (context `kind-astro-ats-014-playground-080-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod`, and an **egress gateway** — release `istio-egress` in namespace `istio-egress`, pods labelled `istio: egress`, Service type `ClusterIP`. Running, and carrying no traffic.
- The mesh at its `ALLOW_ANY` default.
- Namespace **`bookinfo`**, labelled `istio-injection=enabled`, with a `curl` client pod and `httpbin` (versions `v1` and `v2`, port `8000`).
- Mesh-wide access logs, so the sidecars **and** the egress gateway write one line per request.
- **No `ServiceEntry`, `Gateway` or `VirtualService`.**
- [`../examples/`](../examples/) holds the module's YAML, numbered in the order you apply it, plus [`../examples/cases/`](../examples/cases/) for the break-it cases. Use them if you cloned the repository; the course parts write the same YAML to files for you.

### Outbound internet

The commands reach `httpbin.org` and `www.google.com`. Without outbound internet access you will see network errors rather than mesh behaviour.

## Helpers

Paste these once in each new terminal. The first sends a request (by default to `https://httpbin.org/get`). The other two show the newest access-log line of each hop.

```sh
call_external() { kubectl exec -n bookinfo deploy/curl -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_hop1_sidecar() { kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=1; }     # curl's sidecar
log_hop2_egress() { kubectl logs -n istio-egress deploy/istio-egress --tail=1; }        # egress gateway
```

## Things to try

- Apply only [`01-serviceentry-httpbin-org.yaml`](../examples/01-serviceentry-httpbin-org.yaml) and call out. `log_hop1_sidecar` ends at an internet IP; the gateway logged nothing. A running egress gateway proves nothing about where traffic goes.
- Apply [`02`](../examples/02-gateway-egress-httpbin-org.yaml), [`03`](../examples/03-destinationrule-egress-gateway.yaml) and then [`04`](../examples/04-virtualservice-httpbin-org-via-egress.yaml) — in that order, "make before break". Now hop 1 ends at the egress pod and only hop 2 reaches the internet.
- Case 1: apply [`cases/c1-virtualservice-missing-hop-2.yaml`](../examples/cases/c1-virtualservice-missing-hop-2.yaml). The TLS handshake fails (`000 exit=35`): the gateway has no route onward.
- Case 2: apply [`cases/c2-virtualservice-without-mesh.yaml`](../examples/cases/c2-virtualservice-without-mesh.yaml). The call returns `200` — and goes straight out, past the gateway. Only hop 1 in the log tells you.
- Case 3: with `04` applied, delete `03` and call again. Hop 1 logs `NC`: the subset `httpbin-org` no longer exists. Re-apply `03`.
- Put an *internal* hostname in the `Gateway`'s `servers[].hosts` and watch the gateway refuse the traffic.
- Delete the `ServiceEntry` while leaving everything else and see what breaks.
- Try the exam-style drill in [`practice.md`](practice.md).

The plain-HTTP variant and `sourceLabels` are exercised by the module's graded lab, which runs on a `demo`-profile install.

## Start over without a new cluster

```sh
kubectl delete vs,dr,se,gateways.networking.istio.io --all -n bookinfo
```

## When you're done

```sh
astrona destroy ats-014-playground-080-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
