# Which Workloads Are Actually In The Mesh Sandbox

Welcome to the foundations practice sandbox. Nothing here is broken in a way Kubernetes will tell you about: every pod is `Running`, every Service has endpoints, and every call succeeds. Two workloads are nevertheless outside the mesh, and your job is to find them and bring them in.

## Launching the Lab
Run the following command in your terminal to boot the kind Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-000/module-01/labs/lab-01
```
