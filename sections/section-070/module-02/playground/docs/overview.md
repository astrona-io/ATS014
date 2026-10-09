# Overview: TLS Origination For External Services (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, the `shuttle` client and the `probe` echo server, and then waits. There is no task, no `astrona submit` and no pass or fail. You can explore, break things, run `astrona destroy`, and start over.

## What is in the playground

The playground holds a small mesh with one client and no traffic rules yet:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no gateways). `istiod` is Istio's control plane: it sends configuration and certificates to every sidecar proxy.
- The mesh at its default outbound traffic policy, **`ALLOW_ANY`**, so pods may connect to any host outside the mesh. This module is about whether the sidecar proxy can **read** the request, not about whether the request may leave.
- Mesh-wide **access logs**, so every proxy writes one line per request or connection. You read the shuttle's access log with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1`.
- Namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod gets a sidecar proxy. It holds:
  - **`shuttle`**, a client pod in the mesh. You send every test request from it with `curl`.
  - **`probe`** v1 and v2 behind one Service on port `8000`, an HTTP echo server inside the cluster.
- **No `ServiceEntry`, `VirtualService` or `DestinationRule`.** You write them while you read the module.

This playground calls `httpbin.org` on ports `80` and `443`. **Without outbound internet access you see network failures, not mesh behaviour.** Run a plain `curl https://httpbin.org/get` on your own machine first to check.

## When you are done

```sh
astrona destroy ats-014-playground-070-02
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

Each task below uses the YAML files you wrote while reading the module. The module's parts show the full YAML for every step.

- Call `https://httpbin.org/get` and `http://httpbin.org/get` before you create any object. Both access log lines show `"- - -"` and `PassthroughCluster`.
- Build the three objects one at a time and note the symptom at each stage: a readable but plain HTTP request on port `80`, then `400` from the server, then `200` with `"url": "https://httpbin.org/get"`.
- Move `tls` to the top level of `trafficPolicy`, delete the `VirtualService`, and watch the call fail with `503 UF` and `WRONG_VERSION_NUMBER`.
- Leave `sni` out of the `DestinationRule` and look for `autoSni` in `istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 443 -o json`.
- Keep calling `https://` while TLS origination is on, and see `curl` fail with exit code `35`.
- Add a `timeout` or a retry policy to the `VirtualService`, and call `http://httpbin.org/delay/5` or `http://httpbin.org/status/503`.
