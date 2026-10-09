---
estimated_duration: 3m
---

# Find The Quiet Shadow

Welcome to a repair mission, astronaut. On the planet `starfleet`, a test ship should be receiving a copy of every signal, and it receives nothing. The senders are perfectly happy, so nothing looks wrong.

Your job is to find out why the shadow is quiet, using the shuttle's proxy, the mirror cluster's endpoints and `istioctl analyze`, fix it, and prove that the copies arrive.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-02/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-02-02
```
