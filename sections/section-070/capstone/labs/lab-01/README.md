# Capstone: A Deny-By-Default Integration Layer

This is the Section 070 integration challenge, astronaut. The mesh refuses every destination that is not on its star chart, and you have three jobs at once: let a partner's TLS-only API through and make it visible to the mesh, bring one of your own non-Kubernetes machines in as a first-class member, and leave a third endpoint firmly blocked.

The three modules meet here. All of them are the same `ServiceEntry` object with different fields, and choosing the wrong value for `location` or `protocol` produces a configuration that works for traffic and fails the requirement.

There is no step-by-step guide until you have tried it. Work from the mission briefing.

This capstone needs **no outbound internet access**.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/capstone/labs/lab-01
```
