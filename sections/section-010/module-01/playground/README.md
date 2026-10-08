# Route Requests Within The Mesh — Playground

- **Slug:** ats-014-playground-010-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system in the simulator: it starts a `kind` cluster with Istio
and the Bookinfo sample app, then waits for you, astronaut. Use it alongside the module's parts. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-010-01
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, port forward to Bookinfo, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` + `istiod`) with Helm |
| `bootstrap/deploy.sh` | Namespace `bookinfo` with injection, access logs, Bookinfo, `curl` client, `httpbin` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/01-request-routing/` | Subsets and "all traffic to one version", plus the mistake cases in `cases/` |
| `examples/02-header-based-routing/` | Header, path and query rules, rule order, plus the cases in `cases/` |
| `docs/overview.md` | What is in the box, helpers, things to try |
| `docs/practice.md` | Two exam-style tasks with checked solutions |
