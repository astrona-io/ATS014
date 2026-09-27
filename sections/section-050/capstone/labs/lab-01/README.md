# Section 050 Capstone: A Controlled Chaos Experiment

This is the Section 050 integration challenge. It uses fault injection as what it is actually for — a test harness for the resilience configuration from section 040 — and it asks you to run two experiments at once on one host, each scoped to its own header so neither touches anybody else's traffic.

The result of the first experiment is the interesting part, and it is not what most people predict.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/capstone/labs/lab-01
```
