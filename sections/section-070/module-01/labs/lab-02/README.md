---
estimated_duration: 3m
---

# Reach The Hidden Relay

Welcome to a repair mission, astronaut. The planet `starfleet` is closed to every host off its star chart. A `ServiceEntry` charts the relay, a host in another solar system, and a flight plan gives it a 2 second timeout. Still, every signal from the shuttle to the relay falls into the black hole.

Your job is to find out why with the flight log and the shuttle's own proxy, fix every fault, and prove that the relay answers, the timeout fires, and the rogue host stays blocked. This lab needs no outbound internet access.

## Launching the Lab

Run this command to start the cluster with the faults already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-070/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-070-01-02
```
