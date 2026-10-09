# Locality Load Balancing And Failover — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-04
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A single sandbox environment that starts a fresh cluster, installs Istio, the `shuttle` client pod and the
`probe` echo server in two zones, and stays running so you can explore the module's topic. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-040-04
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-040-04`), not the
configuration path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime and bootstrap only) |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` and `istiod`) with Helm |
| `bootstrap/deploy.sh` | Labels the node `local/zone-a`, creates namespace `starfleet` with access logs, the `shuttle` client and the `probe` echo server in two zones |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `docs/overview.md` | What the environment contains, helpers and practice tasks |
