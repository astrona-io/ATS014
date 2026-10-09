# TLS Origination At The Egress Gateway — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-080-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system for astronauts: a single sandbox environment that spins up, installs Istio with Helm (including an egress gateway in `istio-egress`), the `shuttle` test client in namespace `starfleet`, and a partner server in namespace `outpost` that only accepts mutual TLS. It stays running so you can explore the module's topic. Nothing to submit. Needs outbound internet access, and `openssl` on your machine to make the partner's certificates.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-080-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-080-02`), not the configuration path. `astrona submit` and `astrona test` do not apply — there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime + bootstrap only) |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base`, `istiod` with DNS capture, egress gateway `istio-egress`) |
| `bootstrap/deploy.sh` | Namespace `starfleet` (injected), mesh-wide access logs, the `shuttle`, the certificates, the partner server and the `partner-client-cert` Secret |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `docs/overview.md` | What the environment contains and ideas to try |
