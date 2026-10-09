---
estimated_duration: 3m
---

# Retire A Subset Without Failed Requests Lab

This graded lab checks one skill: changing live routing in the safe order. In the namespace `starfleet`, every request to `scout` still goes to the old subset `v1`. The task is to retire `v1`: all clients move to `v2`, the end user `jason` gets `v3`, and the `v1` subset is removed from the `DestinationRule`.

The hard part is not the YAML. A client pod, `patrol`, sends a request to `scout` twice a second for the whole lab, and every one of them must succeed. If a route ever points at a subset that is already gone, the `patrol` proxy's access log shows a `503`, and the lab fails.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-03-01
```
