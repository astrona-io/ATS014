# Locality Load Balancing And Failover Sandbox

Welcome to the Module 4 targeted practice sandbox. In this lab you'll make traffic leave a locality whose endpoint is failing — which means configuring the thing that decides what "failing" means, because locality settings on their own never fail over.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-04/labs/lab-01
```
