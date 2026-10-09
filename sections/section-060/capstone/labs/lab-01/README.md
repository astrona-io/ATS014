---
estimated_duration: 60m
---

# Capstone: Expose Three Services Through Three Ingress APIs Lab

The capstone lab for this section. The learner exposes three applications at the same time on one cluster, each through a different ingress API: Istio's own `Gateway` and `VirtualService`, the Kubernetes `Ingress` API, and the Kubernetes Gateway API.

The goal is not to build a real edge this way. The three APIs are different objects, with different owners, different proxies and different features. Running all three side by side, and checking which proxy pod answers which request, is the fastest way to stop confusing them.

There is no step-by-step guide until the learner has tried the task. The learner works from the specification in `question.md`.

## Launching the Lab

Run this command to start the `kind` Kubernetes cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-060
```
