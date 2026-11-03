---
estimated_duration: 25m
---

# Split A Probe Route Table Across Delegates Lab

This graded lab checks one skill: splitting the route table of one host across a root `VirtualService` and two delegate `VirtualService` objects. In the namespace `starfleet`, the Service `probe` has two versions and a `DestinationRule` with the subsets `v1` and `v2`. There is no `VirtualService` yet. The task is to write the root and the two delegates so that `/hostname` goes to `v2`, `/delay` requests get a 2 second timeout, and every other request goes to `v1`.

This lab is UNTESTED: it was written and checked statically, and it has not been run on a cluster yet.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-04/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/module-04/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-010-04-01
```
