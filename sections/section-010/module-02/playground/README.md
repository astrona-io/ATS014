# Scope Proxy Configuration With The Sidecar Resource — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-010-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

An ungraded environment for this module: it starts a `kind` cluster, installs Istio, creates the `starfleet` and `outpost` namespaces with their workloads, and keeps running so the learner can try the `Sidecar` resource. Nothing to submit.

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
| `bootstrap/deploy.sh` | Creates the namespaces, turns on access logs and starts the workloads |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies: namespaces, access logs, shuttle, cargo and probe |
| `docs/overview.md` | What the environment contains, and practice tasks |
