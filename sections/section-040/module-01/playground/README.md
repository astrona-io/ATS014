# Timeouts And Retries — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system for astronauts: a sandbox that starts up, installs Istio and the Bookinfo apps, and then waits
for you. Use it to try every "Try it" step in this module. Nothing to submit.

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
| `config.yaml` | Environment definition: runtime, port forward to Bookinfo, the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm: `istio-base` (the CRDs) and `istiod` |
| `bootstrap/deploy.sh` | Creates namespace `bookinfo` and applies everything in `bootstrap/manifests/` plus Bookinfo |
| `bootstrap/manifests/` | Namespace, access logs, `curl` client, `httpbin` v1/v2, `reviews` subsets, the jason → v2 route |
| `examples/04-timeouts/` | The timeout steps, numbered in the order you apply them, and `cases/` |
| `examples/06-retries/` | The retry steps, numbered in the order you apply them, and `cases/` |
| `docs/overview.md` | What the environment contains, helper functions and ideas to try |
| `docs/practice.md` | Two exam-style tasks with checked solutions |
