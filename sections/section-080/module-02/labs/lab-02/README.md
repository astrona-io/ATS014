---
estimated_duration: 25m
---

# Open The Partner's Locked Door

Welcome to a repair mission, astronaut. Signals from the planet `starfleet` to the partner should leave through the departure gate (the egress gateway), and the gate should show the partner a client certificate in a mutual TLS handshake. The route is written and the client certificate was delivered. But every signal bounces off the partner's locked door.

Your job is to find out why with the flight logs, the gate's keys and mission control's log, fix every fault, and prove that the partner accepts the gate's certificate. This lab needs no outbound internet access.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-02-02
```
