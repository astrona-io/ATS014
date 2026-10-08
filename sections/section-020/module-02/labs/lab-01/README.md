# Mirror Live Traffic To A Shadow Service Sandbox

Welcome to the Module 2 targeted practice sandbox, astronaut. Your mission: let a test ship hear every signal while nobody hears its replies. In this lab you'll send every caller response from the stable version while a copy of each request goes to a shadow — then prove the shadow received it, using the one piece of evidence the caller can never show you.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-01
```
