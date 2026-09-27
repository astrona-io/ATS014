# Ingress With The Kubernetes Gateway API Sandbox

Welcome to the Module 3 targeted practice sandbox. In this lab you'll create a Gateway that brings its own proxy with it, then let a route from a *different* namespace attach to it — which this API denies by default.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
```
