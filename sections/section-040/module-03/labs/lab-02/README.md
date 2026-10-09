---
estimated_duration: 3m
---

# Raise Both Shields

Welcome to a shield mission, astronaut. On the planet `starfleet`, the probe has three ships, and one of them answers every signal with `503` while Kubernetes calls it healthy. Nothing protects the probe from too many signals at once either.

Your job is to protect the probe with both halves of a circuit breaker in one `DestinationRule`: a connection pool that refuses overflow signals, and outlier detection that pulls the broken ship out of formation. Then prove each half works.

## Launching the Lab

Run this command to start the cluster with the broken ship already in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-040-03-02
```
