---
estimated_duration: 15m
---

# Open The Spaceport Gate

Welcome to a building mission, astronaut. On the planet `starfleet`, a flight plan for the bridge is ready and waiting. It names a gate, `starfleet-gateway`, but nobody has built that gate yet, so no signal from outside can reach the bridge.

Your job is to build the gate with a Gateway API `Gateway`, check that Istio built its proxy on the right planet, and prove that signals for `starfleet.example.com` reach the bridge through it.

## Launching the Lab

Run this command to start the cluster with the waiting flight plan in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03-02
```
