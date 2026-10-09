---
estimated_duration: 45m
---

# Route One Workload Through The Egress Gateway Lab

This graded lab is a build task. An egress gateway is already running, and no request goes through it yet. You route one outside host through it, prove the extra hop from the egress gateway's own access log, and limit the route to one workload. Then you see what that limit really means: the other workload still reaches the host, directly.

This lab needs **no outbound internet access**. The "outside" endpoint is a pod that is deliberately not in the mesh's service registry.

## Running the lab

Start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-080/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-080-01
```
