# Outlier Detection And Endpoint Ejection — Playground

- **ID:** PLAYGROUND
- **Slug:** ats-014-playground-040-03
- **Author:** Paris Nakita Kejser
- **Type:** Astrona playground — clean environment, no task, no grading



A single sandbox environment that spins up, runs OS prep, and stays running so
you can explore the module's topic on a clean machine. Nothing to submit.

## Run it

```sh
astrona run -c .
astrona destroy ats-014-playground-040-03
```

`astrona destroy` takes the environment name (`metadata.name` = `ats-014-playground-040-03`), not
the config path. `astrona submit` and `astrona test` do not apply — there is no
grading.

## Layout

| Path | Purpose |
| --- | --- |
| `config.yaml` | Environment definition (runtime + bootstrap only) |
| `bootstrap/prepare.sh` | OS prep run once at startup: istioctl + Istio control plane + sidecar check |
| `manifests/lab-start.yaml` | Starting workloads applied at bootstrap (copied from the matching `domains/` lab) |
| `docs/overview.md` | What the environment contains and ideas to try |
