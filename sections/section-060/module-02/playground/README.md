# Expose A Service With A Kubernetes Ingress — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-060-02
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading



A training solar system that spins up, runs Operating system preparation, and stays running so
you can explore the module's topic on a clean machine. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-060-02
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-060-02`), not
the configuration path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime + bootstrap only) |
| `bootstrap/prepare.sh` | Operating system preparation run once at startup: istioctl + Istio control plane + sidecar check |
| `manifests/lab-start.yaml` | Starting workloads applied at bootstrap (copied from the matching `domains/` lab) |
| `docs/overview.md` | What the environment contains and ideas to try |
