# Scope Proxy Configuration With The Sidecar Resource — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-010-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system in the simulator: it spins up, installs Istio and two planets with their ships, and stays running so you, astronaut, can explore the module's topic. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-010-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-010-02`), not the configuration path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime and bootstrap only) |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` and `istiod`) with Helm |
| `bootstrap/deploy.sh` | Creates the planets, turns on access logs and starts the ships |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies: planets, access logs, shuttle, cargo and probe |
| `docs/overview.md` | What the environment contains and ideas to try |
