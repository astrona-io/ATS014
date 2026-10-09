---
estimated_duration: 5m
---

# Give Every Ship Its Orbit

Welcome to a repair mission, astronaut. On the planet `starfleet`, the flight plan for the probe is correct: it keeps signals in the shuttle's own orbit. Yet the shuttle's signals still spread over two probes. One ship sits in the wrong orbit.

Your job is to find that ship with the shuttle's endpoint list, put it in its own orbit, and prove that the shuttle's signals stay close to home.

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
