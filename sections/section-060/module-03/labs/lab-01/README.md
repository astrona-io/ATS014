---
estimated_duration: 30m
---

# Share One Gateway Between Two Planets

Welcome to a building mission, astronaut. Two crews on two different planets (namespaces) both need signals from outside the solar system. You build one shared gate for them with a Gateway API `Gateway`, which brings its own proxy with it. Then you let a route from the *other* planet dock at it, which this API refuses by default.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03
```
