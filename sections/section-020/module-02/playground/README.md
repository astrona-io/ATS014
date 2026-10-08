# Mirror Live Traffic To A Shadow Service — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-020-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading

A sandbox (a training solar system) with the echo `probe` in two versions that spins
up, installs Istio, and stays running so you can try traffic mirroring on a
clean cluster. Nothing to
submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-020-02
```

`astrona destroy` takes the environment name (`metadata.name` =
`ats-014-playground-020-02`), not the configuration path. `astrona submit` and
`astrona test` do not apply — there is no grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition: kind runtime and two bootstrap scripts |
| `bootstrap/install-istio.sh` | Installs Istio 1.30.5 with Helm (`istio-base` + `istiod`) |
| `bootstrap/deploy.sh` | Namespace `starfleet`, access logs, `shuttle`, `probe` v1/v2 |
| `bootstrap/manifests/` | The YAML `deploy.sh` applies |
| `examples/` | The module's DestinationRule and VirtualServices, numbered in the order you apply them, plus `cases/` |
| `docs/overview.md` | What the environment contains, the helpers, ideas to try |
| `docs/practice.md` | An exam-style drill with a checked solution |
