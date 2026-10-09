# Add External Workloads With WorkloadEntry — Playground

- **Slug:** ats-014-playground-070-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system in the simulator: it starts a `kind` cluster with Istio,
the shuttle and two old freighters that stand in for virtual machines, then
waits for you, astronaut. Use it alongside the module's parts. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-070-03
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime and the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` + `istiod` with DNS capture) with Helm |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, the `shuttle` client and the two freighters |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies; `freighter.yaml` holds the stand-in machines |
| `docs/overview.md` | What is in the box, where the stand-in stops, things to try |
