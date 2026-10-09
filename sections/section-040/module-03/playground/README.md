# Outlier Detection And Endpoint Ejection — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A practice cluster with the HTTP echo server `probe` in two versions, the
`shuttle` test client and the `fortio` load generator. It starts, installs
Istio, and stays running so you can practise outlier detection and endpoint
ejection on a clean cluster. Nothing to submit.

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
| `examples/` | Authors' reference YAML: the broken pod, the outlier detection rule, and three variations in `cases/` |
| `docs/overview.md` | The only learner page: what the environment contains, the helpers, ideas to try, and a final `## Practice tasks` section |
