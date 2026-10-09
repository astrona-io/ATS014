---
estimated_duration: 5m
---

# Split Traffic Between Two Zones With Distribute

In this lab, the `shuttle` pod in namespace `starfleet` sends every request to the `probe` Service to the probe in its own zone. That is fast, but the probe in the other zone receives no requests, so nobody knows whether the path to it still works.

Your job is to replace the locality preference with a fixed split in the `probe` `DestinationRule`: most requests stay in the client's zone, and a set share goes to the other zone on purpose.

## Launching the Lab

Run this command to start the cluster in its starting state:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-03
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-04/labs/lab-03
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-04-03
```
