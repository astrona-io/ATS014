# Load Balancer Policy And Session Affinity Sandbox

Welcome to the Module 1 targeted practice sandbox, astronaut. On this mission you'll pin users to endpoints with consistent hashing, then override that policy for one subset only — and prove from the proxy's own configuration that the two clusters really are using different algorithms.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-01
```
