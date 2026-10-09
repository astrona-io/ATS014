# Expose A Service With An Istio Ingress Gateway — Playground

- **Slug:** ats-014-playground-060-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system in the simulator: it starts a `kind` cluster with Istio, an ingress gateway
and the Starfleet (the Istio docs' Bookinfo sample, renamed), then waits for you, astronaut. Use it
alongside the module's parts. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-060-01
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, port forwards to the bridge and the ingress gateway, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` and `istiod` in `istio-system`, the ingress gateway in `istio-ingress` |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, the Starfleet, `shuttle` client, `probe` v1/v2, the `scout` subsets |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's numbered YAML (`01-…`, `02-…`, `03-…`) |
| `examples/cases/` | The YAML for each mistake case in the overview |
| `docs/overview.md` | What is in the box, the helper, things to try |
| `docs/practice.md` | An exam-style task with a checked solution |
