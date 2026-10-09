---
estimated_duration: 3m
---

# Fix A Hidden ServiceEntry And Its Port Protocol

This is a troubleshooting lab. The `starfleet` namespace refuses every host that is not in the service registry (`REGISTRY_ONLY` on its `Sidecar` resource). A `ServiceEntry` adds an external host called `relay` to the registry, and a `VirtualService` gives it a 2 second timeout. Still, the `shuttle` pod's sidecar proxy refuses every request to the relay.

Your job is to find out why with the access log and `istioctl proxy-config`, fix every fault, and prove that the relay answers, the timeout fires, and the `rogue` host stays blocked. This lab needs no outbound internet access.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-01-02
```
