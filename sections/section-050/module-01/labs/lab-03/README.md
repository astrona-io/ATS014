---
estimated_duration: 15m
---

# Stop The Drill That Never Ended

Welcome to a repair mission, astronaut. On the planet `starfleet`, somebody ran an abort drill on the navigation computer and never cleaned it up. Every scout answer now arrives without its star ratings, for every crew on the planet.

Your job is to keep the drill for test signals only, and to give everyone else their star ratings back.

## Launching the Lab

Run this command to start the cluster with the problem already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-050/module-01/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-050-01-03
```
