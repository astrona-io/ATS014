# Section 030 Capstone: Sticky Sessions With A Shadowed Canary

This is the Section 030 integration challenge. It combines this section's `trafficPolicy` work — host-level session affinity with a subset-level override — with section 020's mirroring, on one host at the same time.

The two features touch different halves of the request path, which is the point: a mirror changes *where a copy goes*, and a load balancer policy changes *which endpoint inside a cluster serves it*. Getting one right does not get the other right, and the policy that applies to the mirrored copy is the mirror target's, not the caller's.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/capstone/labs/lab-01
```
