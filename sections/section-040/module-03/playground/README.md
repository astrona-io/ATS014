# Outlier Detection And Endpoint Ejection — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system for astronauts: a single sandbox environment that starts, installs Istio and the apps, and stays
running so you can explore the module on a clean cluster. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-040-03
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-040-03`), not
the configuration path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: name, docs, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Helm: `istio-base` + `istiod` 1.30.5 in `istio-system` |
| `bootstrap/deploy.sh` | Namespace `bookinfo` (injection on), mesh access logs, `curl`, `httpbin` v1/v2, `fortio` |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's YAML: the broken pod, the outlier rule and two cases |
| `docs/overview.md` | What the environment contains, helpers and ideas to try |
| `docs/practice.md` | Exam-style drill covering both halves of circuit breaking, with a checked solution |
