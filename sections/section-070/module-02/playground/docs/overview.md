# Overview: TLS Origination For External Services (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: your training solar system, astronaut. It
starts a fresh cluster, installs Istio, the shuttle and the probe, and then
waits. There is no task, no `astrona submit` and no pass or fail. Explore,
break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `kubectl` is already pointed at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no
  gateways). `istiod` is mission control: it sends every proxy its orders.
- The mesh at its **`ALLOW_ANY`** default, so ships may signal any outside
  planet. This module is about whether the communications officer can **read**
  the signal, not about whether it may leave.
- Mesh-wide **access logs**, so every proxy writes one line per signal. This
  is the ship's flight log, and you read it with
  `kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1`.
- Namespace **`starfleet`** (the planet you work on), labelled
  `istio-injection=enabled`, with:
  - **`shuttle`**, your client pod inside the mesh. You send every test signal
    from it with the `curl` command.
  - **`probe`** v1 and v2 behind one Service on port `8000`, an echo service
    inside the cluster.
- **No `ServiceEntry`, `VirtualService` or `DestinationRule`.** Writing them is
  the module.

### Outbound internet

This playground calls `httpbin.org` on ports `80` and `443`. **Without outbound
internet access you see network failures, not mesh behaviour.** Run a plain
`curl https://httpbin.org/get` on your own machine first.

## Things to try

Each idea below uses the files you made while reading the module. The
module's parts show the full YAML for every step.

- Call `https://httpbin.org/get` and `http://httpbin.org/get` before anything
  else. Both log lines show `"- - -"` and `PassthroughCluster`.
- Build the three objects one at a time and note the symptom of each stage:
  a readable but open signal on port `80`, then `400` from the server, then
  `200` with `"url": "https://httpbin.org/get"`.
- Move `tls` to the top of `trafficPolicy`, delete the `VirtualService`, and
  watch the call fail with `503 UF` and `WRONG_VERSION_NUMBER`.
- Leave `sni` out and look for `autoSni` in
  `istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 443 -o json`.
- Keep calling `https://` with origination switched on: `curl` exit code `35`.
- Add a `timeout` or a retry policy to the flight plan and call
  `http://httpbin.org/delay/5` or `http://httpbin.org/status/503`.

## When you're done

```sh
astrona destroy ats-014-playground-070-02
```

(`astrona destroy` takes the environment name, not the configuration path.)
