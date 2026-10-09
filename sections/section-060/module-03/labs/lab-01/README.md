---
estimated_duration: 30m
---

# Share One Gateway API Gateway Across Two Namespaces Lab

A build lab. Two teams in two namespaces both need requests from outside the cluster. The learner creates one shared Gateway API `Gateway`, for which Istio deploys its own proxy. Then the learner lets an `HTTPRoute` from the *other* namespace attach to it, which the Gateway API refuses by default, using a namespace label selector in `allowedRoutes`.

## Launching the Lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-03/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-03/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-03
```
