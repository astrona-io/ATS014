# Route Requests By Header, URI And Query Parameter Sandbox

Welcome to the Module 1 targeted practice sandbox. In this lab you'll split one Kubernetes Service into named subsets and route individual requests to a chosen version based on a header, a URI prefix and a query parameter — then prove the rule order is right by sending traffic that must *not* match.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
```
