# Overview: Secure An Istio Ingress Gateway With TLS (Playground)

This is a playground, not a lab. It starts a fresh cluster, installs Istio, its ingress gateway and the example workloads, and then waits. There is no task, no `astrona submit` and no pass or fail. You can explore, break things, run `astrona destroy` and start over.

Here you secure the ingress gateway with TLS (Transport Layer Security). The `tls` block of an Istio `Gateway` object makes the gateway terminate HTTPS, redirect HTTP to HTTPS, require client certificates, or pass encrypted traffic through to a backend.

## What's in the box

The playground holds one cluster with Istio, the gateway and the example workloads:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod` (Istio's control plane, which sends configuration to every proxy) and the **ingress gateway** `istio-ingressgateway` in `istio-system`. Its pods carry the label `istio: ingressgateway`, which your `Gateway` objects select.
- Mesh-wide **access logs**: every proxy writes one line per request. Read the gateway's log with `kubectl logs -n istio-system deploy/istio-ingressgateway`.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, with:
  - `bridge`, the web frontend (its page is `/productpage` on port `9080`), and the backends it calls: `cargo`, `navcom` and `scout` v1/v2/v3.
  - **`probe`** v1 and v2, an HTTP echo server on port `8000`. It answers any path under `/anything`, and `/hostname` returns the name of the pod that answered.
  - **`archive`**, an nginx server that terminates TLS itself on port `8443`, behind the Service `archive` on port `443`. It has no sidecar proxy and its own certificate for `archive.starfleet.example.com`. It answers every request with `{"service":"archive"}`.
  - **`shuttle`**, a test client pod inside the mesh.
- **No `Gateway`, no `VirtualService` and no gateway certificate.** Writing them is the point of the module.

## Reaching the gateway

The playground forwards two ports on your machine to the gateway:

| On your machine | Gateway port |
| --- | --- |
| `http://localhost:8080` | `80` |
| `https://localhost:8443` | `443` (once a `Gateway` with an HTTPS server and its secret exist) |

Paste this once in each new terminal:

```sh
GATEWAY_URL=localhost:8080
```

For HTTPS, send requests with `curl -sk --resolve <host>:8443:127.0.0.1 https://<host>:8443/<path>`. The `--resolve` flag makes curl send the host name in the TLS handshake (SNI, Server Name Indication), and `-k` accepts a self-signed certificate.

## The helper script

The playground ships the helper script `https-status.sh`. It sends one HTTPS request through the gateway for a path, with a host name (`starfleet.example.com` unless you name another host), and prints only the HTTP status code.

Use it like this: `astrona res run https-status.sh -- /productpage`, or `astrona res run https-status.sh -- /get probe.example.com`.

## Start over without a new cluster

These commands remove the objects and secrets that the module creates:

```sh
kubectl delete gateway,virtualservice --all -n starfleet
kubectl delete secret starfleet-tls probe-tls secure-tls -n istio-system --ignore-not-found
kubectl delete secret probe-tls -n starfleet --ignore-not-found
```

The secret `archive-tls` in `starfleet` belongs to the `archive` pod. Do not delete it.

## Playground not working?

- `astrona list` shows the running environments. If `astrona run` says "already exists", an old one is still there: run `astrona destroy ats-014-playground-060-04`, then run again.
- `astrona run` prints the full log path at the end (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, switch back: `kubectl config use-context kind-astro-ats-014-playground-060-04`.
- If `curl` prints `000` on port `8443`, check three things: the `Gateway` has an HTTPS server for that host, `istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system` shows the secret as `ACTIVE`, and your `--resolve` flag uses the same host name as the `Gateway`.
- If a port forward does not answer, check it with `astrona port-forward list`.

## When you're done

`astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-060-04
```

## Practice tasks

Each task is a small change to the files you made while reading the module. Edit your saved file (for example `gateway-starfleet-gateway.yaml`), apply it with `kubectl apply -f`, and watch what happens. Always test with `curl` and read `istioctl proxy-config secret`.

1. Change `credentialName` of the `starfleet.example.com` server to a name that does not exist. The HTTPS request fails, and the secret shows as `WARMING`. Read the `istiod` log with `kubectl logs -n istio-system deploy/istiod | grep <name>` to see where Istio looked.
2. Move `starfleet-tls` to the `starfleet` namespace, and delete the copy in `istio-system`. Compare what you see with task 1.
3. Add `tls.httpsRedirect: true` to the port 80 server, then remove it. Send a plain HTTP request each time and read the status code.
4. Remove `ca.crt` from `secure-tls` (create the secret again without that key). Send a request with the client certificate and see that it fails. Add the key back.
5. Send a request to `secure.starfleet.example.com` with a client certificate that a different CA signed. Make a second CA and a second client certificate with `openssl`.
6. Change the `archive` server from `PASSTHROUGH` with `protocol: TLS` to `SIMPLE` with `protocol: HTTPS` and `credentialName: archive-tls` placed in `istio-system`. The gateway now terminates TLS itself. Check with `openssl s_client` which certificate it presents.
7. Compare `istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system --port 443` before and after each change.
