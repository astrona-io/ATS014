# Timeouts And Retries — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A sandbox that starts a `kind` cluster, installs Istio and the Starfleet sample app, and then waits. Use it for
every hands-on step in this module. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-040-01
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-040-01`), not
the configuration path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: runtime, port forward to the bridge, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` (the CRDs) and `istiod` |
| `bootstrap/deploy.sh` | Creates the `starfleet` namespace and applies everything in `bootstrap/manifests/` |
| `bootstrap/manifests/` | Namespace, access logs, the Starfleet, the shuttle, the probe v1/v2, the scout subsets and the `VirtualService` that sends `end-user: jason` to scout v2 |
| `examples/` | Every `VirtualService` and `DestinationRule` the module's parts save, for authors who cloned the repository |
| `docs/overview.md` | The learner page: what the environment contains, helper functions, ideas to try and a final `## Practice tasks` section |
