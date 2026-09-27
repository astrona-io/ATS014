# TLS Origination For External Services Sandbox

Welcome to the Module 2 targeted practice sandbox. The endpoint you must reach speaks **only** TLS, and the client will call it over plain `http://`. The sidecar has to bridge the gap — and the endpoint itself reports which scheme it was actually reached over, so there is no guessing whether it worked.

This lab needs **no outbound internet access**: the TLS endpoint runs inside the cluster, deliberately outside the mesh registry.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-01
```
