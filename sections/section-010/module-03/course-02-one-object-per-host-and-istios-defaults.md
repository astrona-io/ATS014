# One Object Per Host And Istio's Defaults

Three small facts save time on every change to a mesh. The first is how `kubectl apply` treats an object that you apply twice. The second is why one host should have only one object of each kind. The third is what Istio does when you have written no rule at all. This part shows all three on the live cluster, and ends with a short reference of the response flags in the access log.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground, and the `VirtualService` that sends every request to `v1` saved as `virtualservice-scout.yaml` in your working folder. A `DestinationRule` defines subsets, which are named groups of pods selected by pod labels. A `VirtualService` holds the routing rules that send requests to those subsets.

## One object per name

Two files with the same `metadata.name` and the same kind in the same namespace describe the **same object**. So `kubectl apply` **replaces** the old object. It never adds a second one next to it.

This is useful. You can keep changing one `VirtualService` called `scout`: first "all to v1", then "jason to v2", then a split by weight. Each new file you apply replaces the last.

<!-- astrona:playground:renew -->

To see it, apply the "all to v1" `VirtualService` again, and list the `VirtualService` objects in the namespace:

```sh
kubectl apply -f virtualservice-scout.yaml
kubectl get virtualservice -n starfleet
```

```text
virtualservice.networking.istio.io/scout unchanged
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   41s
```

Now write a second file with the same name, `scout`, that sends everything to `v3` instead. Save this as `virtualservice-scout-v3.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v3
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-v3.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

Then check the result. List the `VirtualService` objects again, and send 10 requests from `shuttle`. Each `scout` response contains the name of the pod that sent it, so `grep` can count the versions:

```sh
kubectl get virtualservice -n starfleet
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

You should see:

```text
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   41s
  10 scout-v3
```

There is still **one** `VirtualService` called `scout`, and every request now goes to `v3`. `kubectl` printed `configured`, not `created`: it changed the existing object.

## One object per host

The other direction is a trap. Do not write several `VirtualService` or `DestinationRule` objects **for the same host** under different names.

Istio merges them only in some cases, for example `VirtualService` objects that are bound to the same gateway. Otherwise there is no defined order between two objects, so you cannot say which rule wins. Keep one `VirtualService` and one `DestinationRule` per host, and put all the rules for that host in them, in the order you want.

## Istio's defaults

When you have written no rule at all, Istio still behaves in a fixed way. Knowing the defaults tells you what a new rule actually changes.

| Setting | Default |
| --- | --- |
| HTTP timeout | None: a request can wait as long as the application takes |
| Retries | 2 retries, for connection failures only. An application's own `503` is not retried |
| Load balancing | `LEAST_REQUEST`: send to the pod with the fewest active requests |
| Requests to unknown outside hosts | `ALLOW_ANY`: let through, with no rules applied (`PassthroughCluster`) |
| Circuit breaker limits | So high that they are in practice unlimited |

You can prove the first two in your playground with the `probe` echo server. There is no `VirtualService` for `probe`, so only the defaults apply to requests to it.

### No rule means no timeout

The path `/delay/3` asks `probe` to wait 3 seconds before it answers. Send one request and print the status code and the time it took:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} after %{time_total}s\n" http://probe:8000/delay/3
```

You should see:

```text
200 after 3.072199s
```

Nothing cut the request short. Without a `timeout`, the `shuttle` proxy waits as long as `probe` takes.

### No retry for the application's own error

The path `/status/503` asks `probe` to answer with its own `503`. Send one request, then read the last line of the `shuttle` proxy's access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/status/503
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line shortened):

```text
503
"GET /status/503 HTTP/1.1" 503 - via_upstream ... outbound|8000||probe.starfleet.svc.cluster.local ...
```

The flag is `-` and the status came `via_upstream`: `probe` itself sent the `503`, not the proxy. Now count how many times each `probe` pod received that request, from the access log of each pod's sidecar proxy:

```sh
kubectl logs -n starfleet deploy/probe-v1 -c istio-proxy | grep -c '/status/503'
kubectl logs -n starfleet deploy/probe-v2 -c istio-proxy | grep -c '/status/503'
```

You should see:

```text
1
0
```

The request arrived exactly **once**. The default retry policy did not send it again, because the error came from the application, not from a failed connection. Your two counts may be swapped, depending on which `probe` pod got the request.

## Response flags: a short reference

The access log has one line for each request that a proxy handles. Each line has a short **response flag** right after the status code. Envoy sets the flag to say what went wrong in the proxy. These are the flags you meet most often:

| Flag | Meaning |
| --- | --- |
| `NR` | No route: no rule matched |
| `NC` | No cluster: the subset does not exist, or has not reached the proxy yet |
| `UH` | No healthy upstream: the cluster has no healthy pods |
| `UT` | Upstream timeout: no response within the `timeout` |
| `URX` | Retry limit exceeded |
| `UO` | Upstream overflow: a circuit breaker refused the request |
| `DI` | Delay injected on purpose by a fault rule |
| `FI` | Fault (abort) injected on purpose by a fault rule |

A `-` in the flag position means no flag: nothing went wrong in the proxy.

## Start a test over

To remove all your rules without building a new cluster, delete every Istio traffic object in the namespace:

```sh
kubectl delete virtualservice,destinationrule,gateways.networking.istio.io,serviceentry,sidecar --all -n starfleet
```

You should see one line for each object that was there, for example:

```text
virtualservice.networking.istio.io "scout" deleted from starfleet namespace
destinationrule.networking.istio.io "scout" deleted from starfleet namespace
```

The full resource name `gateways.networking.istio.io` stops `kubectl` from mixing up Istio's `Gateway` with the `Gateway` of the Kubernetes Gateway API.

You now know that applying a file with an existing name replaces the object, that each host should have one `VirtualService` and one `DestinationRule`, and what Istio does with no rules: no HTTP timeout, two retries for connection failures only, `LEAST_REQUEST` load balancing, outside hosts allowed, and in practice no circuit breaker limits. With the response flags, you can tell which of these behaviours produced a given error.

## Common pitfalls

> [!WARNING]
> - **Expecting a second file to add rules.** Same kind, same name, same namespace: it replaces the object.
> - **Two objects for one host.** Their order is not defined. Put all the rules for a host in one object.
> - **Assuming a default timeout.** There is none for HTTP. A slow application makes every client wait.
> - **Assuming default retries cover application errors.** They cover connection failures only.
> - **Reading a bare `503` without the flag.** `NC`, `UH`, `UO` and `URX` all reach the client as `503`. The flag tells you which fix you need.
