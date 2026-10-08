# TLS Origination At The Egress Gateway Sandbox

Welcome to the Module 2 practice mission, astronaut — the last one in the course. A planet that only accepts encrypted (TLS) signals, a spaceship that only sends plain `http://`, and a departure gate in between that has to do the secure handshake. Five objects, and the endpoint itself tells you whether you got it right.

This lab needs **no outbound internet access**.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
```
