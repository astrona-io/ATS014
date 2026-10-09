---
estimated_duration: 3m
---

# Retire A Ship Class Safely

Welcome to a live-change mission, astronaut. On the planet `starfleet`, every scout signal still flies to the old ship class `v1`. Mission control wants `v1` retired: everyone moves to `v2`, `jason` tests `v3`, and the `v1` subset is removed.

The hard part is not the YAML. A patrol ship sends a signal to the scout twice a second for the whole mission, and every one of them must arrive. If a route ever points at a subset that is already gone, the patrol's flight log shows it, and the mission fails.

## Launching the Lab

Run this command to start the cluster with the starting state in place:

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
