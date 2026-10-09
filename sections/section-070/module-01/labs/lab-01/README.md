---
estimated_duration: 3m
---

# Allow One External Host Under REGISTRY_ONLY

This is a build lab. The mesh already refuses every host that is not in the service registry (`REGISTRY_ONLY`). You add exactly one external endpoint to the registry with a `ServiceEntry`, prove that a second endpoint is still refused, and put a 2 second `VirtualService` timeout on the endpoint you allowed.

This lab needs **no outbound internet access**: the "external" endpoints are ordinary pods that are left out of the service registry on purpose.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-01
```
