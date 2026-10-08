# Expose A Service With An Istio Ingress Gateway — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-060-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system: it starts a `kind` cluster, installs Istio 1.30.5 with an ingress
gateway, deploys Bookinfo, and then waits for you. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-060-01
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-060-01`), not
the configuration path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, two port forwards, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Helm: `istio-base` and `istiod` in `istio-system`, ingress gateway in `istio-ingress` |
| `bootstrap/deploy.sh` | Namespace `bookinfo`, access logs, Bookinfo, `curl`, `httpbin`, the `reviews` subsets |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's numbered YAML (`01-…`, `02-…`, `03-…`), applied in that order |
| `examples/cases/` | The YAML for each case in the overview's "Cases to test" |
| `docs/overview.md` | What the environment contains and ideas to try |
| `docs/practice.md` | An exam-style task with a hidden solution |
