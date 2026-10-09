# Expose A Service With A Kubernetes Ingress — Playground

- **Slug:** ats-014-playground-060-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A clean environment: it starts a `kind` cluster with Istio, its ingress
gateway and the Starfleet example workloads, then waits. Use it alongside the
module's parts. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-060-02
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, port forwards to the ingress gateway (`8080` to `80`, `8443` to `443`), the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base`, `istiod` and the gateway chart released as `istio-ingressgateway`) with Helm |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, the Starfleet, `shuttle` client, `probe` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `docs/overview.md` | What is in the box, helpers and practice tasks |
