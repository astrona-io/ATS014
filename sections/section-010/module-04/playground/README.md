# Compose And Scope VirtualServices With delegate And exportTo - Playground

- **Slug:** ats-014-playground-010-04
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground - clean environment, no task, no grading

An ungraded environment: it starts a `kind` cluster with Istio and the `probe` echo server
in two versions, then waits. A second namespace, `dock`, has sidecar injection and its own
client pod, so you can see which `VirtualService` and `DestinationRule` objects reach which
namespace. Use it alongside the module's parts. There is nothing to submit.

This playground is UNTESTED: it was written without starting a cluster.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-010-04
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime and the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` and `istiod` in `istio-system` |
| `bootstrap/deploy.sh` | Namespaces `starfleet` and `dock`, access logs, the `probe`, its subsets and three client pods |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `resources/count-versions.sh` | Helper: sends 10 requests from a client pod and counts which `probe` version answered |
| `examples/` | The module's numbered YAML, one file per part |
| `examples/cases/` | The YAML for each practice case |
| `docs/overview.md` | The only learner page: what is in the playground, the helper, things to try, and a final `## Practice tasks` section |
