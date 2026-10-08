# Welcome, Astronaut

This course trains you for the **Traffic Management** part of the **Istio Certified Associate (ICA)** exam. That part is 35% of the exam, the biggest single piece of it.

## Who this course is for

You know your way around Kubernetes: namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`. You do not need to know Istio yet. The course starts from the beginning.

## What you can do at the end

The exam is hands-on. You get a live cluster and a list of tasks, and you have to make them work. So this course does not ask you to remember words. It asks you to *do* things, and to prove they work:

- Send signals (requests) to the right version of a service, by header, path or weight.
- Set how signals reach a service: load balancing, connection limits, and which pods to stop using.
- Make services survive failures with timeouts, retries, circuit breakers and failover.
- Test that with fake failures (fault injection).
- Let traffic into the mesh and out of it, through gateways and to services outside the cluster.
- Find out *why* something does not work, by asking the proxy what it actually holds.

Everything is built and checked on **Istio 1.30.5**.

## The picture we use: space

Istio has a lot of new words. To make them stick, this course uses one picture from start to finish: space.

You are an astronaut. Your Kubernetes cluster is a **solar system**. Each namespace is a **planet**, and each pod is a **spaceship**. A request one ship sends to another is a **signal**.

Istio puts a **communications officer** on board every ship: the sidecar proxy. Every signal in or out goes through them. **Mission control** (`istiod`) gives every communications officer their orders. Each page uses one short picture like this the first time a new word appears, and then sticks to the real term.

## How the course is laid out

The course has nine sections. Each section is one topic from the exam, except section 000, which is pre-flight training that everything else needs.

Each section has one or more **modules**. A module has four kinds of pages:

| What | What it is for | Graded? |
| --- | --- | --- |
| **Reading** | A short landing page, then a few parts that teach one idea each | No |
| **Playground** | A training solar system on your own machine, to try everything you read | No |
| **Lab** | A real mission: a task, a live cluster, and a grader that checks your work | Yes |
| **Capstone** | The last mission in a section, using everything in it at once | Yes |

The best order for each module: read the parts with the playground open next to them, clean up the playground, then take the lab without looking at the solution. Finish each section with its capstone.

## How to read a page

Three kinds of boxes come back on almost every page.

> [!TIP]
> **Try it.** A short hands-on step for the playground. Run it: you learn more from one real result than from a page of text.

> [!WARNING]
> **Common pitfalls.** The mistakes people make most often with what you just learned, and how to spot them.

> [!NOTE]
> **A note.** Something worth knowing that is not the main point.

Code blocks are exactly what you type or what you will see. Never change a command to make it "look right". If the result is different from the page, that difference is the lesson.
