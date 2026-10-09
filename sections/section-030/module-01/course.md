# Load Balancer Policy And Session Affinity

A Kubernetes Service is usually backed by several pods. Each request still goes to just one of them, and the sidecar proxy of the sending pod picks which one. The **sidecar proxy** is the Envoy proxy container that Istio adds to each pod; all traffic of the pod passes through it. Picking the pod is called **load balancing**, and in this module you take control of it.

There are two reasons to control it. The first is **efficiency**: some requests cost much more than others, and simple turn-taking can send a heavy request to a pod that is already busy. The second is **session affinity**, also called stickiness: some applications keep each user's data in memory, so the same user must keep reaching the same pod.

Both are set in the same place: the `trafficPolicy.loadBalancer` field of a `DestinationRule`, the Istio object that holds policies for traffic to one host.

## Learning objectives

After this module you can:

- Explain where picking a pod happens, compared with matching a rule and picking a subset.
- Set `trafficPolicy.loadBalancer.simple` and say what `ROUND_ROBIN`, `LEAST_REQUEST`, `RANDOM` and `PASSTHROUGH` each do, and when each is the right choice.
- Configure session affinity with `consistentHash` over a header, a cookie, a query parameter or the source IP.
- Predict what happens to sticky sessions when pods are added or removed, and to a request that carries nothing to hash.
- Explain why stickiness does not keep a user on one version in a weighted split.
- Set a `trafficPolicy` at host, subset or port level, and say exactly which settings a subset inherits from the host and which it loses.
- Read `lbPolicy` and the ring settings from a live proxy with `istioctl proxy-config cluster`.

## What you should know first

You should know that `istiod`, Istio's control plane, sends configuration to every sidecar proxy, and that `istioctl proxy-config` prints the configuration a proxy holds. You should also know the `DestinationRule` subsets: named groups of a host's pods, chosen by pod labels. A `VirtualService`, the Istio object that holds routing rules, sends requests to a subset. This module adds a second field to the same `DestinationRule`; it needs no new object.

## Your playground

The playground is one `kind` cluster with Istio 1.30.5, installed with Helm, and access logs switched on for every proxy. Everything runs in the `starfleet` namespace, with sidecar injection on. The `probe` Service on port `8000` has four pods behind it: three `probe-v1` pods and one `probe-v2` pod. Its path `/hostname` returns the name of the pod that served the request. The `shuttle` pod is the client; you send every test request from it.

The probe has four pods because with only one pod you could not tell stickiness from luck. There is no `DestinationRule` yet, so Istio's default load balancer is in force. Start the playground now and keep it running while you read the parts:

<!-- astrona:playground -->

## The order of the parts

The module has five parts. The first part shows where the proxy picks a pod, how to watch it in the access log, and the four `simple` algorithms that spread requests. A lab follows, where you fix a policy that sends every request to one pod.

The second part turns to `consistentHash`, which pins a user to one pod by hashing a request header. It explains the hash ring, why stickiness is best effort, and what happens to a request with nothing to hash. The third part covers the other values you can hash: a cookie that the proxy can create itself, the source IP address, and a query parameter.

The fourth part gives one subset its own load balancer and shows exactly what a subset inherits from the host. A lab follows, where you keep one subset sticky and spread another. The fifth part puts a policy on one port and maps the words of a task to the right form. Its lab asks you to keep browsers sticky with a cookie on one port. A short summary closes the module.
