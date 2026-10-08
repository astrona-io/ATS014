# Capstone: Route And Scope A Storefront

Astronaut, this is your Section 010 capstone mission: the integration challenge. It combines both modules — subsets and request matching from Module 1, configuration scoping from Module 2 — into one specification you have to deliver on a mesh with no traffic configuration at all.

The two halves interact, which is the point: a `Sidecar` that is too narrow will break routing you got right, and a routing rule pointing at a subset the proxy was never told about fails the same way as a subset that does not exist.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/capstone/labs/lab-01
```
