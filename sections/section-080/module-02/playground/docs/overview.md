# Overview: TLS Origination At The Egress Gateway (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab. The environment starts clean, installs Istio, an egress gateway, your test shuttle and a partner server, and then waits. There is no task, no `astrona submit`, and no pass/fail. Explore, break things, `astrona destroy`, start over.

Welcome aboard, astronaut. Think of your cluster as a solar system and each namespace as a planet. Each pod is a spaceship, and its sidecar is the communications officer that every signal goes through. The egress gateway is the solar system's departure gate: one checked exit for signals leaving it. In this playground the gate also puts the TLS lock on outgoing signals, and shows a client certificate when a partner asks for one.

## What's in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it (context `kind-astro-ats-014-playground-080-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod` with **DNS capture** on (a ship can look up a `ServiceEntry` host by name), and an **egress gateway**: release `istio-egress` in namespace `istio-egress`, pods labelled `istio: egress`, Service type `ClusterIP` with ports `80` and `443`.
- The mesh at its `ALLOW_ANY` default.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with the **`shuttle`** test client.
- The `Secret` **`partner-client-cert`** in `starfleet`: the client certificate (`tls.crt`, `tls.key`) and the partner's certificate authority (`ca.crt`).
- Namespace **`outpost`**, **not** in the mesh, with the **`partner`** server behind the Service `partner` on port `443`. It only speaks HTTPS, and only answers callers that show a client certificate signed by the "Outpost Root CA". It answers with what it saw, for example `client=CN=starfleet-departure-gate verify=SUCCESS`.
- Mesh-wide access logs, so the shuttle's sidecar **and** the gate write one line per signal.
- **No `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`.** Writing them is the module.

### Outbound internet

The first parts call `httpbin.org`. Without outbound internet access you will see network errors rather than mesh behaviour. The partner server needs no internet access.

## Helpers

Paste these once in each new terminal:

```sh
call_httpbin() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 15 -w "\n%{http_code}\n" http://httpbin.org/get | grep -E '"url"|^[0-9]{3}$'; }
call_partner() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 10 -w "%{http_code}\n" http://partner.outpost.example/; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

## Things to try

- Build the five-object chain for `httpbin.org` and compare the `transportSocket` count of the gate and the shuttle, with and without `exportTo`.
- Route stage 2 to port `80` instead of `443`, and read the `url` field and the gate's upstream port.
- Put the TLS settings on the gate's own Service and read the shuttle's flight log.
- Route the partner through the gate with `SIMPLE`, then `MUTUAL`, and read the gate's flight log after each step.
- Point `credentialName` at a `Secret` that only exists in `starfleet`, then look at `istioctl proxy-config secret deploy/istio-egress -n istio-egress` and the `istiod` log.

## Start over without a new cluster

```sh
kubectl delete vs,dr,se,gateways.networking.istio.io --all -n starfleet
kubectl delete secret partner-client-cert -n istio-egress --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-080-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
