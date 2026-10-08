# Load Balancer Policy And Session Affinity — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-030-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

Your training solar system in the simulator, astronaut. It starts a small
cluster, installs Istio and the test apps, and then waits for you. You explore
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
| `bootstrap/deploy.sh` | Creates namespace `bookinfo`, turns on access logs, deploys `curl` and httpbin, scales httpbin v1 to 3 pods |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's DestinationRules, numbered in the order the module uses them |
| `examples/cases/` | Extra cases to test (source IP, query parameter, a policy per subset) |
| `docs/overview.md` | What is in the environment, the helper function, and things to try |
| `docs/practice.md` | An exam-style task with a checked solution |
