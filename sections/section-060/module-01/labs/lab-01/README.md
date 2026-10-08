# Expose A Service With An Istio Ingress Gateway Sandbox

Welcome aboard, astronaut. This is the Module 1 training mission. You'll open a listener on the shared ingress gateway, attach two applications to it by hostname, and prove from the gateway's own route table that both really landed. Signals from outside the solar system should reach the right ship, and only the right ship.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
```
