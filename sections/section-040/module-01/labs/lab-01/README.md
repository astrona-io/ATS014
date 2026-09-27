# Timeouts And Retries Sandbox

Welcome to the Module 1 targeted practice sandbox. In this lab you'll bound a request with a deadline, retry the read path, and deliberately *not* retry the write path — then prove from the server's own log how many attempts each one really made.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-01
```
