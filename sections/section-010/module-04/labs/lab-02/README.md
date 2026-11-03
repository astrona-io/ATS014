---
estimated_duration: 15m
---

# Show A VirtualService To The Namespaces That Need It Lab

This graded lab checks one skill: finding and fixing a `VirtualService` that some namespaces cannot see. In the namespace `starfleet`, a `VirtualService` sends all `probe` requests to subset `v2`. It works from `starfleet`, but the client in the namespace `dock` still reaches both versions. The task is to find out why and to fix it for `dock` without changing the behaviour of the namespace `depot`.

This lab is UNTESTED: it was written and checked statically, and it has not been run on a cluster yet.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-04/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-04/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-04-02
```
