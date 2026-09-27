# Expose A Service With An Istio Ingress Gateway Sandbox

Welcome to the Module 1 targeted practice sandbox. In this lab you'll open a listener on the shared ingress gateway, attach two applications to it by hostname, and prove from the gateway's own route table that both really landed.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
```
