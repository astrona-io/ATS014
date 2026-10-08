# Route External Traffic Through An Egress Gateway — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-080-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system for astronauts: a single sandbox environment that spins up, installs Istio with Helm (including an egress gateway in `istio-egress`) plus a `curl` client and `httpbin` in namespace `bookinfo`, and stays running so you can explore the module's topic. Nothing to submit. Needs outbound internet access.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-080-01
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-080-01`), not the configuration path. `astrona submit` and `astrona test` do not apply — there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime + bootstrap only) |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base`, `istiod`, egress gateway `istio-egress`) |
| `bootstrap/deploy.sh` | Namespace `bookinfo` (injected), mesh-wide access logs, `curl` and `httpbin` |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's YAML, numbered in apply order; `examples/cases/` holds the break-it cases |
| `docs/overview.md` | What the environment contains and ideas to try |
| `docs/practice.md` | An exam-style drill with a checked solution |
