---
estimated_duration: 60m
---

# Register An External API And A Virtual Machine In A REGISTRY_ONLY Mesh Capstone Lab

This is the integration lab for the section on connecting in-mesh workloads to external workloads and services. The mesh blocks every outbound destination that is not in its service registry (`outboundTrafficPolicy.mode: REGISTRY_ONLY`). You have three jobs at once:

- Let a partner API that only accepts TLS through, with the sidecar proxy originating the TLS connection.
- Add one machine that runs outside Kubernetes as a member of the mesh, with an identity.
- Leave a third endpoint blocked.

All three jobs use the same `ServiceEntry` kind with different fields. A wrong value for `location` or `protocol` gives a configuration where requests work and the requirement still fails.

There is no step-by-step guide until you have tried it. Work from the task in `question.md`.

This capstone needs **no outbound internet access**.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-070
```
