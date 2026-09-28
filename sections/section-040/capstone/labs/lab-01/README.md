# Capstone: A Resilient Payment Path

This is the Section 040 integration challenge. All four of the section's features act on one service at the same time: a deadline and a retry policy that differ between reads and writes, a connection pool that refuses work the caller cannot do promptly, outlier detection that removes an endpoint which keeps failing, and locality awareness on top.

They interact, which is the point. Retries are extra concurrent work aimed at a pool that may already be full. Retries also hide from the caller the very failures outlier detection needs to observe. And a locality setting without outlier detection does nothing at all.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/capstone/labs/lab-01
```
