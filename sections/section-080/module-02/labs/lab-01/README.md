---
estimated_duration: 45m
---

# Lock The Signal At The Departure Gate

Welcome to a build mission, astronaut. A partner planet only accepts sealed (TLS) signals, your ship only sends plain `http://`, and the departure gate (the egress gateway) in between has to put the lock on. You write five objects, and the partner itself tells you whether you got it right: it answers with the scheme it was reached over.

This lab runs its own small app on the `demo` install of Istio: the client is `tester` in the namespace `egwtls-demo`, and the gate is `istio-egressgateway` in `istio-system`. It needs **no** outbound internet access.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-02/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-02
```
