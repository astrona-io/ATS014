# Capstone: One Exit, Two Partners

This is the Section 080 final mission, astronaut, and the last practical exercise in the course. One departure gate (egress gateway) carries signals to two planets outside the solar system: one over plain HTTP, one TLS-only, with the handshake done at the gate. Only one of your two spaceships (workloads) is routed through it.

Everything composes here — a `ServiceEntry` from section 070, a `Gateway` and two-stage `VirtualService` objects from module 1, `portLevelSettings` precedence from section 030, and `sourceLabels` matching from section 010. Five objects per host, two hosts, one gateway.

There is no step-by-step guide until you have tried it. Work from the specification.

This capstone needs **no outbound internet access**.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/capstone/labs/lab-01
```
