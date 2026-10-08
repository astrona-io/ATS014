# Session Affinity For Browsers Sandbox

Welcome to the Module 1 second practice sandbox, astronaut. Lab 1 pinned a user with a header that somebody else had to set. This one handles the case where nobody sets anything: the client is a browser, its signals arrive with no call sign, and Istio has to issue one itself — attached at the port level rather than to the whole host.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-02
```
