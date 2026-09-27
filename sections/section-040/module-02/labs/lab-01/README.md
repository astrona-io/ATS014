# Circuit Breaking With Connection Pool Limits Sandbox

Welcome to the Module 2 targeted practice sandbox. In this lab you'll cap the concurrent work a caller may have outstanding, then prove the cap is real — by showing that the same total number of requests succeeds sequentially and fails concurrently.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-02/labs/lab-01
```
