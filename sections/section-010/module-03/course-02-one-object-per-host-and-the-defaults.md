# One Object Per Host, And The Defaults

Part 1 was about the order between objects. This part covers three smaller things that save you time in every later section: how `kubectl apply` treats an object you apply twice, why one host should have one object of each kind, and what Istio does when you have written nothing at all.

## One object per name

Two files with the same `metadata.name` in the same namespace describe the **same object**. So `kubectl apply` **replaces** the old one. It does not add a second one.

The course uses this on purpose. Many steps change the same `VirtualService` called `scout`: first "all to v1", then "jason to v2", then a weighted split. Each new file replaces the last.

> [!TIP]
> **Try it: apply replaces, it does not add**
>
> ```sh
> kubectl apply -f virtualservice-scout.yaml
> kubectl get virtualservice -n starfleet
> sed 's/subset: v1/subset: v3/' virtualservice-scout.yaml > virtualservice-scout-v3.yaml
> kubectl apply -f virtualservice-scout-v3.yaml
> kubectl get virtualservice -n starfleet
> ```
>
> This uses the `virtualservice-scout.yaml` from Part 1, with the `DestinationRule` in place. Both listings show **one** `VirtualService` named `scout`. The second apply says `configured`, not `created`. Every call to `scout` now gets v3.

## One object per host

The other direction is a trap. Avoid writing several `VirtualService` or `DestinationRule` objects **for the same host** under different names.

Istio only combines them in some cases, for example `VirtualService` objects linked to the same gateway. Otherwise, the result is hard to predict. There is no defined order between two objects, so you cannot say which rule wins. Keep one `VirtualService` and one `DestinationRule` per host, and put all of that host's rules in them, in the order you want.

## Defaults worth remembering

When you have written no rule at all, Istio still does something. Knowing the defaults tells you what a new rule actually changes.

| Setting | Default | Taught in |
| --- | --- | --- |
| HTTP timeout | none: a request can wait as long as the app takes | section 040 |
| Retries | 2 retries, for connection errors only. An app's own `503` is not retried | section 040 |
| Load balancing | `LEAST_REQUEST`: send to the pod with the fewest active requests | section 030 |
| Calls to unknown outside hosts | `ALLOW_ANY`: let through, with no rules (`PassthroughCluster`) | section 070 |
| Circuit breaker limits | so high they are effectively unlimited | section 040 |

> [!TIP]
> **Try it: no rule, no timeout**
>
> ```sh
> time kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/delay/3
> ```
>
> The `probe` (the echo probe) waits 3 seconds before it answers. With no `VirtualService`, nothing cuts the call short: you get `200` after a little over 3 seconds. Section 040 shows how a `timeout` changes that.

## Response flags: a quick reference

The access log is the ship's black box flight log. Each line has a short **response flag** for what went wrong. [Section 000, part 3](../../section-000/module-01/course-03-the-diagnostic-toolkit.md) explains how to read them, and `NR` and `UH` in depth. This table lists the flags the course meets, and where each is taught:

| Flag | Meaning | Taught in |
| --- | --- | --- |
| `NR` | no route: no rule matched | section 000; module 01, part 3 |
| `NC` | no cluster: the subset does not exist (yet) | module 01, part 3; this module, part 1 |
| `UH` | no healthy upstream: the cluster has no working pods | section 000; module 01, part 1 |
| `UT` | upstream timeout | section 040 |
| `URX` | retry limit exceeded | section 040 |
| `UO` | upstream overflow: a circuit breaker said no | section 040 |
| `DI` | delay injected | section 050 |
| `FI` | fault (abort) injected | section 050 |

`-` in the flag position means no flag: nothing went wrong in the proxy.

## Start a test over

To clear your rules without building a new cluster:

```bash
kubectl delete virtualservice,destinationrule,gateways.networking.istio.io,serviceentry,sidecar --all -n starfleet
```

The full resource name `gateways.networking.istio.io` keeps `kubectl` from mixing up Istio's `Gateway` with the Kubernetes Gateway API's `Gateway`.

## Common pitfalls

> [!WARNING]
> - **Expecting a second file to add rules.** Same name, same namespace: it replaces the object.
> - **Two objects for one host.** Their order is not defined. Put all of a host's rules in one object.
> - **Assuming a default timeout.** There is none for HTTP. A slow app makes every caller wait.
> - **Assuming default retries cover app errors.** They cover connection errors only.
> - **Reading a bare `503` without the flag.** `NC`, `UH`, `UO` and `URX` all reach the caller as `503`. The flag tells you which fix you need.

> *One host, one object of each kind. And always know what the default was before you change it.*
