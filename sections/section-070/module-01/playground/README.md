# Control External Access With ServiceEntry — Playground

- **Slug:** ats-014-playground-070-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

An ungraded sandbox: it starts a `kind` cluster with Istio, the `shuttle` client and the `probe` echo server in the namespace `starfleet`, then waits. Use it next to the module's parts. There is nothing to submit.

**Needs outbound internet access.** The module calls `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org` and `www.google.com` from inside the cluster.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-070-01
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 (`istio-base` + `istiod`) with Helm, at the `ALLOW_ANY` default |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, `shuttle` client, `probe` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's `Sidecar`, `ServiceEntry` and `VirtualService` YAML, plus the mistake cases in `cases/` |
| `docs/overview.md` | The only learner page: what is in the playground, the helper, things to try, and a final `## Practice tasks` section with a checked solution |
