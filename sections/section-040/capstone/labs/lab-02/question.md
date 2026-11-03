# Question

Solve this question on: `terminal`

The `shuttle` pod calls the `probe` Service. Its nearest endpoint is broken, slow requests hold callers for too long, and connections are not managed at all. Fix this with configuration on the calling side only.

The namespace `starfleet` runs on a cluster with one node. The node has the labels region `local` and zone `zone-a`. Three Deployments run there:

| Deployment | What it is | Locality |
| --- | --- | --- |
| `shuttle` | Test client pod with a sidecar proxy. You send every test request from here | `local/zone-a`, the node's locality |
| `probe-zone-a-damaged` | A pod that answers `503` to every request but stays ready | `local/zone-a` |
| `probe-zone-b` | A healthy HTTP echo server (go-httpbin) | `local/zone-b` |

A **locality** is the region, zone and subzone a pod runs in. The probe pods set theirs with the `istio-locality` label. Both probe Deployments sit behind the `probe` Service on port `8000`. The path `/hostname` returns the name of the pod that served the request, and `/delay/<seconds>` answers after that many seconds.

No `VirtualService`, no `DestinationRule` and no `trafficDistribution` exists yet.

## Your task

1. Make the `probe` Service prefer endpoints that are close to the client, with the Kubernetes `Service` field for it. Keep its selector and port as they are.
2. Create a `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe` with these settings:
   - the connect timeout is `2s`
   - the HTTP idle timeout is `60s`
   - the maximum connection duration is `5m`
   - TCP keepalive starts probing after `30s` of idle time, sends a probe every `10s`, and gives up after `3` unanswered probes
   - outlier detection ejects an endpoint after `2` consecutive `5xx` errors, checked every `5s`, for a base ejection time of `30s`, and it can eject up to `100` percent of the endpoints
3. Create a `VirtualService` named `probe` in the namespace `starfleet` for the host `probe` that routes every request to the `probe` host with a route timeout of `3s`, and retries with `2` attempts, a per-try timeout of `1s` and `5xx` as the retry condition.
4. Prove the result with live requests from `shuttle`: after the failing pod has been ejected, 20 requests to `http://probe:8000/hostname` all return status code `200` and are all answered by `probe-zone-b`, and a request to `http://probe:8000/delay/5` returns `504` after about three seconds.

## Rules

- The preference for nearby endpoints must come from the `Service`. Do not set `localityLbSetting` in the `DestinationRule`.
- Create one `DestinationRule` and one `VirtualService`, both named `probe`.
- Do not scale, add or remove Deployments, and do not change the node's labels or the pod localities. The failing pod must stay in place: the proxy has to eject it.

## Useful commands

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
```

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
```

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://probe:8000/delay/5
```
