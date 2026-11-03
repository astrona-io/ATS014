# TLS Settings In A DestinationRule — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-030-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading
- **Status:** UNTESTED. Written and checked statically only; it has not been started with `astrona run` yet.

An ungraded environment for this module. It starts a small `kind` cluster,
installs Istio and the test workloads, and then waits. The learner explores
the module's topic on it. There is nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-030-02
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-030-02`), not the configuration path. `astrona submit` and
`astrona test` do not apply, because there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: name and the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` (CRDs) and `istiod` |
| `bootstrap/deploy.sh` | Creates `starfleet` (access logs, shuttle, probe v1 with 3 pods and v2 with 1 pod) and `outpost` (the drifter, no sidecar) |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `resources/` | Helper scripts: `count-pods.sh`, `status-codes.sh`, `drifter-call.sh` |
| `examples/` | Reference YAML for authors (not on the learner's machine) |
| `docs/overview.md` | The only learner page: what is in the environment, the helpers, things to try, and a final `## Practice tasks` section |
