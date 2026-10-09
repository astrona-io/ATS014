# Mesh Foundations

Before you give Istio any rules, you need to know what Istio already does on its own. This section shows that.

Istio adds a **sidecar proxy** (Envoy) to every pod in the mesh. The sidecar proxy is a second container next to your application, and all traffic in and out of the pod passes through it. Istio's control plane, **`istiod`**, sends every proxy its configuration and keeps it up to date while the proxy runs.

When you label a namespace for Istio, three things happen to each new pod that launches there. It gets a proxy. Its traffic is sent through that proxy. And `istiod` sends the proxy a full set of settings. All of this happens before you write a single Istio object.

This section shows you what Istio adds to a pod, how `istiod` sets up the proxies, and a few commands that show what a proxy knows right now. You will not write any Istio traffic rules here.

---

## What You Will Master

- What Istio adds to a pod when it injects a proxy (the "sidecar"), and why labelling a namespace does not change pods that are already running.
- How `iptables` rules (the Linux firewall) send a pod's own traffic through the proxy on ports `15001` and `15006`, without the app knowing.
- Why every request inside the mesh is logged twice, and what a caller without a proxy misses out on.
- What the **service registry** is (the list of hosts and endpoints `istiod` knows about), what it is built from, and how `istiod` turns it into settings for Envoy, the proxy Istio uses.
- LDS (Listener Discovery Service), RDS (Route Discovery Service), CDS (Cluster Discovery Service) and EDS (Endpoint Discovery Service): the four kinds of settings `istiod` sends to each proxy, what each one holds, and why the proxy can take new settings without a restart.
- The chain a request follows inside a proxy: listener → route → cluster → endpoint. You will learn to read each step with `istioctl proxy-config`.
- How to read an Envoy cluster name, which tells you the direction, port, subset and host.
- The order to check things in when something goes wrong: `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, then the access log. You will also learn what each one cannot show you.
- The short codes in the Envoy access log, called response flags, and why `NR` and `UH` point at opposite halves of your setup.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary.

### How A Request Moves Through The Mesh

5 parts and 2 labs:

1. What Sidecar Injection Adds To A Pod
2. Follow A Request Through Two Proxies
   - Lab: Bring Workloads Into The Mesh With Sidecar Injection Lab
3. How istiod Sends Configuration Over xDS
4. Read Listeners, Routes, Clusters And Endpoints
5. Diagnose The Mesh With istioctl And Access Logs
   - Lab: Fix A Service Selector That Matches No Pod Lab
6. Summary
