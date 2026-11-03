# Question

Solve this question on: `terminal`

Callers of the `probe` Service wait too long on connections that do not open, and a firewall in the network drops idle connections after two minutes without anyone noticing.

The namespace `starfleet` runs on a cluster with one node. Three Deployments run there:

| Deployment | What it is |
| --- | --- |
| `shuttle` | Test client pod with a sidecar proxy. You send every test request from here |
| `probe-zone-a` | HTTP echo server (go-httpbin) |
| `probe-zone-b` | HTTP echo server (go-httpbin) |

Both probe Deployments sit behind the `probe` Service on port `8000`. Its `/hostname` path returns the name of the pod that served the request. No `DestinationRule` and no `VirtualService` exists yet.

## Your task

1. Create one `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe`, with these connection pool settings:
   - the connect timeout is `2s`
   - the HTTP idle timeout is `90s`
   - the maximum connection duration is `10m`
   - TCP keepalive starts probing after `60s` of idle time, sends a probe every `10s`, and gives up after `4` unanswered probes
2. Show from the proxy of `shuttle` that its cluster for `probe.starfleet.svc.cluster.local` on port `8000` holds all of these values.
3. Show that 10 requests from `shuttle` to `http://probe:8000/hostname` all return status code `200`.

## Rules

- Create no second `DestinationRule` for the host, and no `VirtualService`.
- Do not use subsets and do not set `outlierDetection` or a load balancer policy: this task is only about the connection pool.
- Do not change, scale, add or remove Deployments, and do not change the `probe` Service.

## Useful commands

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
```

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/hostname
```
