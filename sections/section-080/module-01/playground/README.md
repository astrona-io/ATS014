# Route External Traffic Through An Egress Gateway — Playground

- **Slug:** ats-014-playground-080-01
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A training solar system in the simulator: it starts a `kind` cluster with Istio, an egress gateway in `istio-egress`, and the `shuttle` client in namespace `starfleet`, then waits for you, astronaut. Use it alongside the module's parts. Nothing to submit.

**Needs outbound internet access.** The module calls `https://httpbin.org` and `https://www.google.com` from inside the cluster.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-080-01
```

`astrona destroy` takes the environment name (`metadata.name`), not the configuration
path. `astrona submit` and `astrona test` do not apply: there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: the two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base`, `istiod`, egress gateway `istio-egress`) |
| `bootstrap/deploy.sh` | Namespace `starfleet` with injection, access logs, and the `shuttle` client |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's `ServiceEntry`, `Gateway`, `DestinationRule` and `VirtualService` YAML, plus the mistake cases in `cases/` |
| `docs/overview.md` | What is in the box, the helpers, things to try |
| `docs/practice.md` | An exam-style task with a checked solution |
