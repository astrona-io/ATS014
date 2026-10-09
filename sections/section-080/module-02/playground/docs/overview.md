# Overview: TLS Origination At The Egress Gateway (Playground)

This is a **playground**, not a lab. The environment starts clean, installs Istio, an egress gateway, a test client and a partner server, and then waits. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, run `astrona destroy`, and start over.

The playground is for TLS origination at the egress gateway. The **egress gateway** is an Envoy proxy at the edge of the mesh that outgoing traffic passes through before it leaves the cluster. **TLS origination** means that a proxy, not the application, opens the TLS (Transport Layer Security) connection to the external server. Here the egress gateway starts TLS for outgoing requests, and presents a client certificate when a partner server asks for one.

## What is in the box

- A single-node `kind` Kubernetes cluster with `kubectl` already pointed at it (context `kind-astro-ats-014-playground-080-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod` with **DNS capture** on (the sidecar proxy answers DNS lookups for hosts that a `ServiceEntry` defines), and an **egress gateway**: release `istio-egress` in namespace `istio-egress`, pods labelled `istio: egress`, Service type `ClusterIP` with ports `80` and `443`.
- The mesh at its `ALLOW_ANY` default, so pods may call any external host.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with the **`shuttle`** test client.
- The `Secret` **`partner-client-cert`** in `starfleet`: the client certificate (`tls.crt`), its private key (`tls.key`) and the partner's certificate authority (`ca.crt`).
- Namespace **`outpost`**, **not** in the mesh, with the **`partner`** server behind the Service `partner` on port `443`. It only speaks HTTPS, and only answers callers that present a client certificate signed by the "Outpost Root CA". It answers with what it received, for example `client=CN=starfleet-departure-gate verify=SUCCESS`.
- Mesh-wide access logs, so the shuttle's sidecar proxy **and** the egress gateway write one line per request.
- **No `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`.** You write them yourself.

The tasks for `httpbin.org` need outbound internet access. Without it you see network errors rather than mesh behaviour. The partner server needs no internet access.

## Helpers

Paste these once in each new terminal. `call_httpbin` and `call_partner` send one plain `http://` request from the shuttle; `log_shuttle` and `log_gate` print the newest access log line of the shuttle's sidecar proxy and of the egress gateway:

```sh
call_httpbin() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 15 -w "\n%{http_code}\n" http://httpbin.org/get | grep -E '"url"|^[0-9]{3}$'; }
call_partner() { kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 10 -w "%{http_code}\n" http://partner.outpost.example/; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

## Start over without a new cluster

These commands remove every Istio object in `starfleet` and the copied `Secret`:

```sh
kubectl delete vs,dr,se,gateways.networking.istio.io --all -n starfleet
kubectl delete secret partner-client-cert -n istio-egress --ignore-not-found
```

## When you are done

```sh
astrona destroy ats-014-playground-080-02
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

- Build the five objects that route `httpbin.org` through the egress gateway with TLS, then compare the `transportSocket` count of the egress gateway and the shuttle, with and without `exportTo`.
- Route the second rule of the `VirtualService` to port `80` instead of `443`, and read the `url` field and the egress gateway's upstream port.
- Put the TLS settings on the egress gateway's own Service and read the shuttle's access log.
- Route the partner server through the egress gateway with `SIMPLE`, then `MUTUAL`, and read the egress gateway's access log after each step.
- Point `credentialName` at a `Secret` that only exists in `starfleet`, then check `istioctl proxy-config secret deploy/istio-egress -n istio-egress` and the `istiod` log.
