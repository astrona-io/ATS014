# One Object Per Host, And The Defaults

Astronaut, three smaller facts save you time on every mission: how `kubectl apply` treats an object you apply twice, why one beacon should have one object of each kind, and what Istio does when you have written no rule at all.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground, and the "all to v1" `virtualservice-scout.yaml` saved in your working folder.

## One object per name

Two files with the same `metadata.name` in the same namespace describe the **same object**. So `kubectl apply` **replaces** the old object. It never adds a second one next to it.

That is useful. You can keep changing one flight plan called `scout`: first "all to v1", then "jason to v2", then a split by weight. Each new file you apply replaces the last.

<!-- astrona:playground:renew -->

### Apply replaces, it does not add

Apply the "all to v1" flight plan again, and list the flight plans on the planet:

```sh
kubectl apply -f virtualservice-scout.yaml
kubectl get virtualservice -n starfleet
```

```text
virtualservice.networking.istio.io/scout unchanged
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   41s
```

Now make a second file with the same name, `scout`, that sends everything to v3 instead. Save this as `virtualservice-scout-v3.yaml`:

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

Then list the flight plans again, and send 10 signals:

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

Still **one** flight plan called `scout`, and every signal now flies to v3. `kubectl` said `configured`, not `created`: it changed the existing object.

## One object per host

The other direction is a trap. Do not write several `VirtualService` or `DestinationRule` objects **for the same host** under different names.

Istio only combines them in some cases, for example `VirtualService` objects linked to the same gateway. Otherwise there is no defined order between two objects, so you cannot say which rule wins. Keep one `VirtualService` and one `DestinationRule` per beacon, and put all of that beacon's rules in them, in the order you want.

## Defaults worth remembering

When you have written no rule at all, Istio still does something. Knowing the defaults tells you what a new rule actually changes.

| Setting | Default |
| --- | --- |
| HTTP timeout | none: a signal can wait as long as the app takes |
| Retries | 2 retries, for connection errors only. An app's own `503` is not retried |
| Load balancing | `LEAST_REQUEST`: send to the ship with the fewest active signals |
| Signals to unknown outside hosts | `ALLOW_ANY`: let through, with no rules (`PassthroughCluster`) |
| Circuit breaker limits | so high they are effectively unlimited |

You can prove the first two in your playground, with the echo probe. There is no flight plan for the probe, so only the defaults apply.

### No rule, no timeout

Ask the probe to wait 3 seconds before it answers:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} after %{time_total}s\n" http://probe:8000/delay/3
```

You should see:

```text
200 after 3.072199s
```

Nothing cut the signal short. Without a `timeout`, the shuttle waits as long as the probe takes.

### No retry for the app's own error

Ask the probe to answer with its own `503`, then read the shuttle's flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/status/503
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line trimmed):

```text
503
"GET /status/503 HTTP/1.1" 503 - via_upstream ... outbound|8000||probe.starfleet.svc.cluster.local ...
```

The flag is `-` and the status came `via_upstream`: the probe itself sent the `503`. Now count how many times each probe ship received that signal:

```sh
kubectl logs -n starfleet deploy/probe-v1 -c istio-proxy | grep -c '/status/503'
kubectl logs -n starfleet deploy/probe-v2 -c istio-proxy | grep -c '/status/503'
```

You should see:

```text
1
0
```

The signal arrived exactly **once**. The default retry policy did not send it again, because the error came from the app, not from a broken connection. Your two counts may be swapped, depending on which probe ship got the signal.

## Response flags: a quick reference

The access log is the ship's black box flight log. Each line has a short **response flag** for what went wrong, right after the status code. These are the flags you will meet on your missions:

| Flag | Meaning |
| --- | --- |
| `NR` | no route: no rule matched |
| `NC` | no cluster: the subset does not exist, or has not arrived yet |
| `UH` | no healthy upstream: the cluster has no working ships |
| `UT` | upstream timeout: no answer within the `timeout` |
| `URX` | retry limit exceeded |
| `UO` | upstream overflow: a circuit breaker said no |
| `DI` | delay injected on purpose |
| `FI` | fault (abort) injected on purpose |

`-` in the flag position means no flag: nothing went wrong in the proxy.

## Start a test over

To clear all your rules without building a new cluster, delete every Istio traffic object on the planet:

```sh
kubectl delete virtualservice,destinationrule,gateways.networking.istio.io,serviceentry,sidecar --all -n starfleet
```

You should see one line for each object that was there, for example:

```text
virtualservice.networking.istio.io "scout" deleted from starfleet namespace
destinationrule.networking.istio.io "scout" deleted from starfleet namespace
```

The full resource name `gateways.networking.istio.io` keeps `kubectl` from mixing up Istio's `Gateway` with the Kubernetes Gateway API's `Gateway`.

## Common pitfalls

> [!WARNING]
> - **Expecting a second file to add rules.** Same name, same namespace: it replaces the object.
> - **Two objects for one host.** Their order is not defined. Put all of a beacon's rules in one object.
> - **Assuming a default timeout.** There is none for HTTP. A slow app makes every sender wait.
> - **Assuming default retries cover app errors.** They cover connection errors only.
> - **Reading a bare `503` without the flag.** `NC`, `UH`, `UO` and `URX` all reach the sender as `503`. The flag tells you which fix you need.

> *One beacon, one object of each kind. And always know what the default was before you change it.*
