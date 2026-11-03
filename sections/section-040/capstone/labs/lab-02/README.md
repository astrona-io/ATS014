---
estimated_duration: 40m
---

# Capstone: Combine Connection Settings, Timeouts, Retries, Outlier Detection And PreferClose

**Status: UNTESTED.** This lab was written and checked statically only (`astrona validate`, `bash -n`). It has not been run with `astrona run` or `astrona test` yet.

This is the second integration lab for the resilience section. One service, `probe`, gets connection settings, a route timeout and retries, outlier detection and a preference for nearby endpoints, all at once. The nearest endpoint is a pod that answers `503` to every request while it stays ready, so the settings must work together: retries hide the first failures from the client, outlier detection ejects the failing pod, and the preference then moves the requests to the other zone.

There is no step-by-step guide until you have tried it. Work from the specification in `question.md`.

## Launching the Lab

Run the following command in your terminal to start the `kind` Kubernetes cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/capstone/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/capstone/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-040-02
```
