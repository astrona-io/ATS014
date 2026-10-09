# Load Balancer Policy And Session Affinity — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-030-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

An ungraded environment for this module. It starts a small `kind` cluster,
installs Istio and the test workloads, and then waits. The learner explores
the module's topic on it. There is nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-030-01
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-030-01`), not the configuration path. `astrona submit` and
`astrona test` do not apply, because there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: name and the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` (CRDs) and `istiod` |
| `bootstrap/deploy.sh` | Creates the `starfleet` namespace, turns on access logs, deploys the shuttle and the probe (3 v1 pods, 1 v2 pod) |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | Reference DestinationRules for authors (not on the learner's machine) |
| `examples/cases/` | Extra cases: source IP, query parameter, a policy per subset |
| `docs/overview.md` | The only learner page: what is in the environment, the helper function, things to try, and a final `## Practice tasks` section |
