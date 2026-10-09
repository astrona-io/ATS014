# Fault Injection With Delays And Aborts — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-050-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system for astronauts: a sandbox that starts up, installs Istio and the Starfleet, and then waits
for you. Use it for every hands-on step in this module. Nothing to submit.

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
| `config.yaml` | Environment definition: runtime, port forward to the bridge, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` (the CRDs) and `istiod` |
| `bootstrap/deploy.sh` | Creates the planet `starfleet` and applies everything in `bootstrap/manifests/` |
| `bootstrap/manifests/` | Namespace, access logs, the Starfleet, the shuttle, the probe v1/v2, and the scout and navcom subsets |
| `examples/` | Every flight plan the module's parts save, numbered in page order, for anyone who cloned the repository |
| `examples/cases/` | The two extra drills from "Things to try" in [`docs/overview.md`](docs/overview.md) |
| `docs/overview.md` | What the environment contains, helper functions and ideas to try |
| `docs/practice.md` | An exam-style task with a checked solution |
