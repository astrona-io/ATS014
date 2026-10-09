---
estimated_duration: 3m
---

# Open Exactly One Route Out

Welcome to a build mission, astronaut. The mesh is already deny-by-default: ships may signal only charted planets, so every external destination is refused. You will chart exactly one of them, prove the other is still blocked, and then put a timeout on the one you allowed, because a charted host is an ordinary host.

This lab needs **no outbound internet access**: the "external" endpoints are ordinary pods deliberately left out of the mesh registry.

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
