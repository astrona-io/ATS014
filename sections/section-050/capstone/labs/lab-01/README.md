# Capstone: A Controlled Chaos Experiment

Astronaut, this is the Section 050 capstone mission. It uses fault injection for what it is really for: a simulation drill for the resilience you built in section 040. You will run two drills at once on one host, each one aimed only at signals carrying its own header, so no other crew is affected.

The result of the first experiment is the interesting part, and it is not what most people predict.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/capstone/labs/lab-01
```
