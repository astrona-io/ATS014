# Outlier Detection And Endpoint Ejection — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A sandbox (a training solar system) with the echo `probe` in two versions, the
`shuttle` and the `fortio` load generator. It spins up, installs Istio, and
stays running so you can pull damaged ships out of formation on a clean
cluster. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-040-03
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-040-03`), not the configuration path. `astrona submit` and
`astrona test` do not apply — there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: name, docs, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base` + `istiod`) |
| `bootstrap/deploy.sh` | Namespace `starfleet`, access logs, `shuttle`, `probe` v1/v2, `fortio` |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's YAML: the broken ship, the outlier rule, and three variations in `cases/` |
| `docs/overview.md` | What the environment contains, the helpers, ideas to try |
| `docs/practice.md` | A practice task covering both halves of a circuit breaker, with a checked solution |
