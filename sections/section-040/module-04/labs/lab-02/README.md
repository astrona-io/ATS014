---
estimated_duration: 5m
---

# Fix An Endpoint In The Wrong Locality

In this lab, the `probe` `DestinationRule` in namespace `starfleet` is correct: it should keep the requests of the `shuttle` pod in its own zone. Yet those requests still go to two probe pods, because one probe pod runs in the wrong locality.

Your job is to find that pod with the endpoint list of the `shuttle` proxy, give it the correct locality, and prove that the requests of `shuttle` stay in its own zone.

## Launching the Lab

Run this command to start the cluster with the fault already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-04/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-04-02
```
