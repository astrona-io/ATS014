---
estimated_duration: 45m
---

# Combine Session Affinity With Traffic Mirroring Capstone Lab

The integration lab for the "Defining Traffic Policies With Destination Rules" section. It combines host-level session affinity with a subset-level load balancer override, and adds traffic mirroring on the same host at the same time.

The two features act on different steps of the request path. Mirroring changes *where a copy of the request goes*. A load balancer policy changes *which endpoint inside a cluster serves it*. Getting one right does not get the other right, and the mirrored copy follows the load balancer of the mirror target's subset, not the caller's.

There is no step-by-step guide on the task page. The learner works from the specification first.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-030/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-030
```
