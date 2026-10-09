# Route Requests By Header, URI And Query Parameter

In this graded lab you split one Kubernetes Service into named subsets with a `DestinationRule`. Then you write a `VirtualService` that routes single requests to a chosen version by a header, a URI prefix and a query parameter. Finally you prove the rule order is right by sending requests that must *not* match.

## Launching the Lab
Run this command in your terminal to start the `kind` Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
```
