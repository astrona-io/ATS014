# TLS Origination For External Services — Playground

- **Slug:** ats-014-playground-070-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

It starts a `kind` cluster with Istio, the `shuttle` client and the `probe` echo service in namespace `starfleet`, then waits. Use it alongside the module's parts. Nothing to submit.

**Needs outbound internet access.** The module calls `httpbin.org` on ports `80` and `443` from inside the cluster.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-070-02
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
| `docs/overview.md` | What is in the box and things to try |
