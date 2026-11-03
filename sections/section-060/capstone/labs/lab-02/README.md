---
estimated_duration: 45m
---

# Capstone: Serve The Starfleet Over HTTPS With Routing Lab

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run against a cluster yet.

The second capstone lab for the ingress section. The learner puts HTTPS on the Istio `Gateway` and combines it with the routing that the section teaches: path matching, a header match that picks a subset, and a `404` for every path that has no route.

There is no step-by-step guide until the learner has tried the task. The learner works from the specification in `question.md`.

## Launching the Lab

Run this command to start the `kind` Kubernetes cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/capstone/labs/lab-02
```

The start script writes a certificate and a key for `starfleet.example.com` to `/tmp/starfleet-edge.crt` and `/tmp/starfleet-edge.key` on your machine.

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/capstone/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-060-02
```
