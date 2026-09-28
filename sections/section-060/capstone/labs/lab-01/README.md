# Capstone: Three APIs, One Edge

This is the Section 060 integration challenge. You expose three applications at once — one through each of the section's three ingress APIs — on the same cluster, at the same time.

The point is not that you would build an edge this way. It is that the three APIs are genuinely different objects with different ownership models, different proxies and different capabilities, and the fastest way to stop confusing them is to run all three side by side and see which pod serves which request.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/capstone/labs/lab-01
```
