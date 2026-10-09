# Route Two External Hosts Through One Egress Gateway Capstone Lab

This is the graded capstone lab of the section. One egress gateway carries requests to two external hosts: one over plain HTTP, and one that only accepts TLS (Transport Layer Security), with the TLS connection started at the egress gateway. Only one of the two client workloads is routed through the egress gateway.

The lab combines everything the section uses: a `ServiceEntry` per external host, one `Gateway` with two listeners, two-stage `VirtualService` objects, `sourceLabels` matching, and a `DestinationRule` with `portLevelSettings` that starts TLS at the egress gateway. That makes eight objects for two hosts and one egress gateway.

There is no step-by-step guide until you have tried it. Work from the task.

This capstone needs **no outbound internet access**.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-080
```
