# What Istio 1.30 and Kubernetes 1.29+ changed under the labs

Every item here was found by running the labs in this series against
Istio 1.30.5 on a `kind` cluster, and every one of them made a grader
report failure for a correctly solved lab, or made a lab impossible to
solve at all. They are recorded here because the same patterns appear in
any check written against an older Istio, in this series or outside it.

Each entry says what to stop doing and what to do instead.

## The sidecar is an init container now

On Kubernetes 1.29+ Istio injects the proxy as a native sidecar, so
`istio-proxy` is in `.spec.initContainers`, not `.spec.containers`. A
check that reads only `containers` reports "no istio-proxy" on a pod that
is injected perfectly well, and one that asserts a pod is *not* injected
passes when it should not.

```sh
# wrong
kubectl get pod "$p" -o jsonpath='{.spec.containers[*].name}'
# right
kubectl get pod "$p" -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}'
```

The same applies to pulling the proxy's image or resources out of the pod:
concatenate both selectors, since only one of them will match.

## The injecting revision is an annotation

`istio.io/rev` is recorded on the pod as an **annotation**. Older releases
wrote a label, and checks that read `.metadata.labels` find nothing on a
workload that was moved onto a canary revision correctly.

```sh
kubectl get pod "$p" -o jsonpath='{.metadata.annotations.istio\.io/rev}'
```

`sidecar.istio.io/status` carries the same revision if you want a second source.

## Inbound listeners live inside virtualInbound

`istioctl proxy-config listener <pod> --port 8084` matches nothing: the
inbound filter chains are inside the `virtualInbound` listener on 15006.
Filtering by the workload port makes mTLS look unconfigured. Read the whole
dump and find the chain whose `filterChainMatch.destinationPort` is the port
you care about, then look at its `transportSocket`.

## A gateway Deployment's image is `auto`

The gateway chart sets `image: auto` and the injector substitutes the real
proxy image when the pod is created. Version checks must read the running
pod, not the Deployment template, or they compare `auto` against a version
and never pass.

## Per-cluster Envoy stats are filtered out

Istio ships a stats matcher that keeps a small set of counters. Per-cluster
ones — `upstream_rq_pending_overflow`, `outlier_detection.*` — are not in it,
so `pilot-agent request GET stats` returns nothing for them and a circuit
breaker or an ejection looks like it never happened. Either annotate the
workload:

```yaml
sidecar.istio.io/statsInclusionPrefixes: "cluster.outbound"
```

or read the admin `/clusters` page, which is not filtered and reports
ejection as a `health_flags::/failed_outlier_check` on the endpoint.

## Mirrored requests are no longer tagged

Istio used to append `-shadow` to the authority of a mirrored copy. It does
not any more, so `grep -- -shadow` finds nothing and a working mirror reads
as broken. Identify copies by the fact that the shadow receives traffic the
route never sends it.

## `ztunnel-config --namespace` is the ztunnel's namespace

`istioctl ztunnel-config workload --namespace my-app` looks for the ztunnel
DaemonSet in `my-app` and fails. List everything and filter the NAMESPACE
column instead. A waypoint attached to a Service also shows in
`istioctl ztunnel-config service`, not in the workload view, whose WAYPOINT
column stays `None` for one.

## A waypoint changes who the peer is

Once a service is enrolled through a waypoint, connections arrive at the pod
from the **waypoint's** identity. A workload-scoped L4 rule naming a client
identity refuses the waypoint and the service answers nobody. Identity for a
waypointed service belongs in a policy attached with `targetRefs`, where the
original client identity is still visible — and the refusal then arrives as
403 rather than a dropped connection.

## Things that are not version drift, but bit us anyway

- **A terminating pod still reports phase `Running`.** Grading right after a
  rollout catches the outgoing replica, which is legitimately on the old
  proxy. Skip pods carrying a `deletionTimestamp`.
- **The injector is not ready when `istioctl install` returns.** A workload
  recreated in that window comes back with no sidecar and nothing reports an
  error. On a revision move, wait for `istio-revision-tag-<tag>`, not for the
  default injector, which exists from the start.
- **istiod's validating webhook is registered before it answers.** Applying an
  Istio object in that window fails with `connection refused` from the webhook.
- **`sed -i` with no argument is GNU-only** and fails on the BSD sed in macOS.
  `sed -i.bak` works on both.
- **`cmd | head` under `set -o pipefail`** exits 141 when head closes the pipe.
