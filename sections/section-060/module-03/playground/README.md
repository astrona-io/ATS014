# Ingress With The Kubernetes Gateway API — Playground

- **Slug:** ats-014-playground-060-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

An ungraded environment: it starts a `kind` cluster with the Gateway API
CRDs, Istio and the Starfleet (the Istio Bookinfo sample with renamed
workloads), then waits. Use it alongside the module's parts. Nothing to
submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-060-03
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, port forward to the bridge, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs the Gateway API objects (v1.3.0), then Istio 1.30.5 (`istio-base` + `istiod`) with Helm, and waits for the `istio` GatewayClass |
| `bootstrap/deploy.sh` | Namespaces `starfleet` and `outpost` with injection, access logs, the Starfleet and `shuttle` in `starfleet`, `probe` v1/v2 in `outpost` |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `docs/overview.md` | What is in the box, things to try |
