# Shift Traffic With Weighted Routing — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-020-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A sandbox with the Starfleet example app that starts a cluster, installs Istio, and
stays running so you can try weighted routing on a clean cluster. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-020-01
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-020-01`), not the configuration path. `astrona submit` and
`astrona test` do not apply — there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, the bridge port forward, two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base` + `istiod`) |
| `bootstrap/deploy.sh` | Namespace `starfleet`, access logs, the Starfleet (`bridge`, `cargo`, `scout` v1-v3, `navcom`), `shuttle`, `probe`, the `scout` DestinationRule |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's VirtualServices, numbered in the order you apply them, plus `cases/` |
| `docs/overview.md` | The only learner page: what the environment contains, the `count_versions` helper, ideas to try, and a final `## Practice tasks` section with a checked solution |
