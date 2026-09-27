# TLS Origination At The Egress Gateway Sandbox

Welcome to the Module 2 targeted practice sandbox — the last one in the course. A TLS-only endpoint, a client speaking plain `http://`, and a gateway in between that has to do the handshake. Five objects, and the endpoint itself tells you whether you got it right.

This lab needs **no outbound internet access**.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
```
