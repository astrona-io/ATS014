---
estimated_duration: 30m
---

# Expose Two Hosts Through One Ingress Gateway Lab

In this lab you open a listener on the shared ingress gateway, bind two applications to it by host name, and prove from the gateway's own route table that both sets of routes arrived. Requests from outside the cluster must reach the right Service, and only the right Service.

The lab uses its own small application (`booking-service` and `catalog-service` in the `ingress-demo` namespace), not the Starfleet. It installs Istio with the `istioctl` `demo` profile, so the gateway runs in `istio-system`.

## Running the lab

Run this command to start the cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-060/module-01/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-060-01
```
