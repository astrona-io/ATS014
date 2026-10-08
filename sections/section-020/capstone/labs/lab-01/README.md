# Capstone: Canary And Shadow At The Same Time

This is the Section 020 integration challenge, astronaut — a full mission with a new ship class on a test flight and a test ship listening in. It puts both of the section's answers to "is the new version safe?" on one rule at the same time: a weighted canary that exposes a slice of real users to the candidate, and a mirror that sends a full copy of the same traffic to a separate shadow service nobody sees.

The two features sit side by side on the same `http` rule and are easy to confuse — a mirror written as a route destination becomes a traffic split, and a weighted destination written as a mirror disappears from the caller entirely.

There is no step-by-step guide until you have tried it. Work from the specification.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/capstone/labs/lab-01
```
