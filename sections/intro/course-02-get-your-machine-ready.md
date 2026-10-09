# Get Your Machine Ready

Every playground and lab in this course runs on your own machine, in a small Kubernetes cluster. A tool called `astrona` builds it for you, sets it up, grades your work and removes it again. This page gets your machine ready.

## What you need

- **A container engine:** Docker or Podman. The cluster runs inside it.
- **`kind`:** runs Kubernetes inside the container engine.
- **`kubectl`:** talks to the cluster.
- **`istioctl`:** Istio's own command-line tool. You use it in almost every module.
- **`helm`:** the newer playgrounds install Istio with it.
- **The astrona command-line tool.**

Let `astrona` check the rest for you:

```sh
astrona setup
```

`astrona setup` looks at what is missing, shows you each step it would take, and asks before it does anything. On macOS it can install `kind`, `kubectl` and Podman. Install `istioctl` and `helm` yourself.

To check your machine at any time:

```sh
astrona check
```

## The four commands you use every day

**1. Sign in.** Labs from the course catalog are tied to your Astrona account:

```sh
astrona login
```

**2. Launch.** Each module page and lab page shows the exact `astrona run` command for its playground or lab. Copy it from there. When the cluster is ready, `kubectl` already points at it.

**3. Submit a lab for grading.** The grader checks the live cluster: it sends real traffic and reads the proxy's configuration, so your work has to actually work, not only exist. Each lab page shows the exact `astrona submit` command. You can submit as often as you like.

**4. Clean up.** When you are done with a playground or a lab, remove it:

```sh
astrona destroy <name>
```

The name is the environment's name, printed by `astrona run` and shown on each page (for example `ats-014-playground-000-01`). It is not the folder path. To see what is running:

```sh
astrona list
```

> [!WARNING]
> **Run one environment at a time.** Each playground and lab is a whole cluster. Two at once slow your machine down, and it is easy to send a command to the wrong one. Destroy the playground before you start the lab.

## When a launch goes wrong

Ask `astrona` what is wrong before you try anything else:

```sh
astrona doctor
```

It checks your machine, the lab's configuration and the running lab, and tells you how to fix what it finds.

Some playgrounds reach the internet (for example `httpbin.org`). If you have no outbound internet, those steps fail with network errors that have nothing to do with Istio. The playground's own page tells you when this applies.
