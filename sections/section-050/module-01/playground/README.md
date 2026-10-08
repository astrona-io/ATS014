# Fault Injection With Delays And Aborts — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-050-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

Your training solar system in the simulator. It starts, installs Istio and the
Bookinfo app (a small fleet of ships), and then waits for you, astronaut. Use it
to run every "Try it" step in this module. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-050-01
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-050-01`), not
the configuration path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime, the Bookinfo port forward, two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base` + `istiod`) |
| `bootstrap/deploy.sh` | Namespace `bookinfo`, access logs, Bookinfo, `curl`, `httpbin`, and the `reviews` and `ratings` subsets |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The YAML the module's "Try it" steps apply, numbered in order, with comments |
| `examples/cases/` | One YAML per case in [`docs/overview.md`](docs/overview.md) |
| `docs/overview.md` | What the environment contains, helper functions, and cases to try |
| `docs/practice.md` | An exam-style task with a checked solution |
