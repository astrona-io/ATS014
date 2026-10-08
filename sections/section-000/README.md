# Mesh Foundations

Welcome aboard, astronaut. Before you give Istio any rules, you need to know what Istio already does on its own. That is your first mission.

Think about your cluster as a solar system. Each namespace is a planet, and each pod is a spaceship. Istio puts a small helper program, deploys a **proxy** as a sidecar alongside your application container, on board every spaceship. The proxy is the ship's communications officer: every signal in or out of the ship goes through them. Istio's control plane, **`istiod`**, is mission control: it radios every communications officer their orders.

When you label a namespace for Istio, three things happen to each new pod that launches there. It gets a proxy. Its traffic is sent through that proxy. And `istiod` sends the proxy a full set of settings. All of this happens before you write a single Istio object.

This section shows you what Istio adds to a pod, how `istiod` sets up the proxies, and a few commands that show what a proxy knows right now. You will not write any Istio traffic rules here.

---

## What You Will Master

- What Istio adds to a pod when it injects a proxy (the "sidecar"), and why labelling a namespace does not change pods that are already running.
- How `iptables` rules (the Linux firewall) send a pod's own traffic through the proxy on ports `15001` and `15006`, without the app knowing.
- Why every request (a signal between ships) inside the mesh is logged twice, and what a caller without a proxy misses out on.
- What the **service registry** is (Istio's star chart: every planet and beacon it knows about), what it is built from, and how `istiod` turns it into settings for Envoy, the proxy Istio uses.
- LDS, RDS, CDS and EDS: the four kinds of settings `istiod` sends to each proxy, what each one holds, and why the proxy can take new settings without a restart.
- The chain a request follows inside a proxy: listener → route → cluster → endpoint. You will learn to read each step with `istioctl proxy-config`.
- How to read an Envoy cluster name, which tells you the direction, port, subset and host.
- The order to check things in when something goes wrong: `kubectl get`, `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, then the access log. You will also learn what each one cannot show you.
- The short codes in the access log (the ship's black box flight log), called response flags, and why `NR` and `UH` point at opposite halves of your setup.
