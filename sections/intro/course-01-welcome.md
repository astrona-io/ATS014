# Welcome To The Course

This course trains you for the **Traffic Management** part of the **Istio Certified Associate (ICA)** exam. That part is 35% of the exam, the biggest single piece of it.

## Who this course is for

You know your way around Kubernetes: namespaces, Deployments, Services, pod labels, `kubectl logs` and `kubectl exec`. You do not need to know Istio yet. The course starts from the beginning.

## What you can do at the end

The exam is hands-on. You get a live cluster and a list of tasks, and you have to make them work. So this course does not ask you to remember words. It asks you to *do* things, and to prove they work:

- Send requests to the right version of a service, by header, path or weight.
- Set how requests reach a service: load balancing, connection limits, and which pods to stop using.
- Make services survive failures with timeouts, retries, circuit breakers and failover.
- Test that with fake failures (fault injection).
- Let traffic into the mesh and out of it, through gateways and to services outside the cluster.
- Find out *why* something does not work, by asking the proxy what it actually holds.

Everything is built and checked on **Istio 1.30.5**.

## The words this course uses

The course uses the real words you will meet in Istio, in its logs and in the exam. Each page explains a term in one plain sentence the first time it appears. A few words come back on almost every page:

- **Service mesh:** a layer that controls how services in a cluster talk to each other, without changes to the applications.
- **Sidecar proxy (Envoy):** a proxy container Istio adds to each pod. All traffic in and out of the pod passes through it, and it applies the routing rules.
- **`istiod`:** Istio's control plane. It turns the cluster's Services and Istio objects into proxy configuration and sends it to every proxy.
- **Request and response:** one HTTP call from a client to a service, and the answer it gets back.
- **`VirtualService` and `DestinationRule`:** the two Istio objects that decide where a request goes and how it reaches the pods.

## The example application

Every playground runs the same example application: the Istio Bookinfo sample, with new Kubernetes names. It runs in the namespace `starfleet`. The `bridge` web front end (`/productpage`) calls the `cargo` service for item details and the `scout` service, which runs in three versions (v1 shows no stars, v2 black stars, v3 red stars). `scout` v2 and v3 call `navcom` for the star rating.

Two more workloads help with tests. `shuttle` is a client pod in the mesh: most test requests are sent from it. `probe` is an HTTP echo server that answers with what it received. A few older labs use their own small applications, and their task page says so.

## How the course is laid out

The course has nine sections. Each section is one topic from the exam, except section 000, which covers the basics that everything else needs.

Each section has one or more **modules**. A module has four kinds of pages:

| What | What it is for | Graded? |
| --- | --- | --- |
| **Reading** | A short landing page, then a few parts that teach one idea each | No |
| **Playground** | A Kubernetes cluster with Istio on your own machine, to try everything you read | No |
| **Lab** | A task, a live cluster, and a grader that checks your work | Yes |
| **Capstone** | The last lab in a section, using everything in it at once | Yes |

The best order for each module: read the parts with the playground open next to them. When a part ends with **Your mission**, pause the playground and take that lab without looking at the solution, then start the playground again and read on. The last page of every module is a summary of what you learned, and it removes the playground. Finish each section with its capstone.

## How to read a page

Most parts follow the same pattern. Each part opens with the problem it solves. Hands-on steps sit inside the text: one or two sentences on what to run and why, the command, the real output, and what it shows. Run them in your playground: you learn more from one real result than from a page of text.

Two kinds of boxes come back often:

> [!TIP]
> **A tip.** A habit or shortcut you can use again, well beyond this one page.

> [!WARNING]
> **Common pitfalls.** The mistakes people make most often with what you just learned, and how to spot them. Every part ends with one.

Code blocks are exactly what you type or what you will see. Never change a command to make it "look right". If the result is different from the page, that difference is the lesson.
