---
estimated_duration: 3m
---

# Bring The Lost Freighters Back

Welcome to a repair mission, astronaut. Two old freighters fly outside the fleet network, on the planet `starfleet`. They have been put on the star chart with `WorkloadEntry` objects and a `ServiceEntry`, but every signal to their name, `freighter.starfleet.mesh`, fails with `503`. And that is not the only thing wrong.

Your job is to find every fault with the flight log and the shuttle's proxy, fix them, and prove that both freighters answer by name, as members of the fleet.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-03-02
```
