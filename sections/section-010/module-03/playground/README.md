# Apply And Remove Traffic Rules Safely — Playground

- **Slug:** ats-014-playground-010-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A clean environment: it starts a `kind` cluster with Istio and the Starfleet
(the Istio Bookinfo sample with other names), then waits. Use it to practise
the order of changes from this module. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-010-03
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, port forward to the bridge, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` + `istiod`) with Helm |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, the fleet (`bridge`, `cargo`, `scout` v1-v3, `navcom`), `shuttle` client, `probe` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | Copies of the `scout` DestinationRule and "all to v1" VirtualService, for someone who has cloned the repository |
| `docs/overview.md` | The learner page: what is in the playground, and practice tasks |
