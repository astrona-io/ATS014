# Shift TCP Connections With Weights — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-020-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading
- **Status:** UNTESTED. This playground was written without being started.

A sandbox cluster with the `probe` HTTP echo server in two versions. It starts,
installs Istio, and stays running so you can try weighted routing for TCP
connections on a clean cluster. You create the second Service (`probe-tcp`),
the `DestinationRule` and the `VirtualService` yourself. There is nothing to
submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-020-03
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-020-03`), not the configuration path.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime and two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base` + `istiod`) |
| `bootstrap/deploy.sh` | Namespace `starfleet`, access logs, `shuttle`, `probe` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `resources/` | Helper scripts: `count-connections.sh` (new connection per sample) and `count-reused.sh` (one connection for all samples) |
| `examples/` | The authors' reference YAML, numbered in the order you apply it, plus `cases/` |
| `docs/overview.md` | The only learner page: what the environment contains, the helpers, ideas to try, and a final `## Practice tasks` section |
