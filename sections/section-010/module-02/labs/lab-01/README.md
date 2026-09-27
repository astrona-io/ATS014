# Scope Proxy Configuration With The Sidecar Resource Sandbox

Welcome to the Module 2 targeted practice sandbox. In this lab you'll cut a proxy's configuration down from the whole service registry to a named list of namespaces, prove the reduction from the proxy's own cluster dump, and show that scoping is a reachability change rather than just a memory saving.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-02/labs/lab-01
```
