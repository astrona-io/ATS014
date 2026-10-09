---
estimated_duration: 15m
---

# Free The Shuttle From A Slow Navcom

Welcome to a repair mission, astronaut. On the planet `starfleet`, a delay drill makes the navigation computer answer 3 seconds late. Someone tried to stop jason waiting that long, but put the abort window in the wrong place, and it never fires.

Your job is to move the abort window to the route that really carries jason's signals, and to prove that the shuttle's own communications officer now gives up after one second.

## Launching the Lab

Run this command to start the cluster with the problem already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-01-02
```
