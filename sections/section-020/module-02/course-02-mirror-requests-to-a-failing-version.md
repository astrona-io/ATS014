# Mirror Requests To A Failing Version

Mirroring is meant for versions you do not trust yet. So the most important promise of a mirror is that a broken shadow cannot hurt the client. The shadow is the destination that receives the copies, and its responses are thrown away. This part tests that promise with a version that fails every request. Then it covers the setting that makes a mirror silently send nothing, mirroring to a separate Service, and the one thing mirroring can never tell you.

The commands below need two saved files in the `starfleet` namespace. `destinationrule-probe.yaml` is a `DestinationRule` named `probe` with the subsets `v1` and `v2` over the `version` label. `virtualservice-probe.yaml` is a `VirtualService` named `probe` that routes every request to `v1` and mirrors 100% to `v2`.

## Watch the client stay healthy while the shadow fails

The test needs a version that returns `503` (Service Unavailable) to every request. You add it as a third Deployment with the label `version: broken`, give it its own subset, and point the mirror at that subset. The Deployment also carries `app: probe`, so the `probe` Service selects its pod too. That is fine here: the route sends every client request to `v1`, so only the mirror ever reaches the broken pod.

<!-- astrona:playground:renew -->

Save this as `deployment-probe-broken.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-broken
  namespace: starfleet
spec:
  replicas: 1
  selector:
    matchLabels:
      app: probe
      version: broken
  template:
    metadata:
      labels:
        app: probe
        version: broken
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:1.0
        args: ["-listen=:8080", "-status-code=503", "-text=broken"]
        ports:
        - containerPort: 8080
```

Apply it:

```sh
kubectl apply -f deployment-probe-broken.yaml
```

Then wait until the pod is ready:

```sh
kubectl rollout status -n starfleet deploy/probe-broken
```

```text
deployment "probe-broken" successfully rolled out
```

The mirror can only point at a subset that a `DestinationRule` defines, so the broken pod needs a subset of its own. Save this as `destinationrule-probe-broken.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: broken
    labels:
      version: broken
```

Apply it:

```sh
kubectl apply -f destinationrule-probe-broken.yaml
```

Now point the mirror at the new subset. Save this as `virtualservice-probe-mirror-broken.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
        subset: v1
    mirror:
      host: probe
      subset: broken
    mirrorPercentage:
      value: 100.0
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-mirror-broken.yaml
```

Then send 5 requests and count the status codes `shuttle` got. After that, count how many copies the proxy of the broken pod logged, and read its last access log line. The access log is the file of one-line records that each sidecar proxy writes, one line per request:

```sh
for i in $(seq 1 5); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://probe:8000/hostname
done | sort | uniq -c
kubectl logs -n starfleet deploy/probe-broken -c istio-proxy --tail=5 | grep -c hostname
kubectl logs -n starfleet deploy/probe-broken -c istio-proxy --tail=1
```

You should see (log line shortened):

```text
      5 200
5
"GET /hostname HTTP/1.1" 503 - via_upstream ... outbound_.8000_.broken_.probe.starfleet.svc.cluster.local default
```

`shuttle` got five `200` responses. The broken pod received every copy and returned `503` to each one, and the client never saw it. The `outbound_.8000_.broken_...` part of the line names the `broken` subset, so the request came in through the mirror. You find the problems of a shadow in its own logs and metrics, never in errors at the client.

Remove the broken Deployment and put back the two-subset `DestinationRule` and the mirror to `v2`:

```sh
kubectl delete -f deployment-probe-broken.yaml
kubectl apply -f destinationrule-probe.yaml
kubectl apply -f virtualservice-probe.yaml
```

## The subset has to exist

The broken pod needed a subset before the mirror could reach it. That is a general rule: Istio looks up `mirror.subset` in the same `DestinationRule` as every other destination. If the mirror names a subset that no `DestinationRule` defines, the mirror **silently sends nothing**. The client still gets a correct response from the route, so nothing looks wrong on the client side.

When a mirror does not work, check in this order:

1. Does the `DestinationRule` define the subset that the `mirror` names? `istioctl analyze` reports it if not.
2. Does that subset select a running pod? `istioctl proxy-config endpoints` on the client pod shows it.
3. Does the client's proxy hold a mirror policy at all? `istioctl proxy-config routes` shows it.

## Mirroring to a separate Service

The mirror target so far was a subset of the same Service, but `mirror` takes any destination. It can also name another host. This piece shows the shape (you do not apply it):

```yaml
mirror:
  host: probe-shadow
  port:
    number: 8000
```

Use that shape when the shadow is a separate Deployment with its own Service and its own datastore. That is usually what you want in production. Mirroring to a subset of the *same* Service is handy for learning, but then the shadow pods sit behind the same Service as the stable pods. Any request that does not pass through your `VirtualService` rule, for example from a client without a sidecar proxy, can reach them too.

## What mirroring cannot tell you

The proxy throws away the shadow's response, so mirroring **cannot compare responses**. It tells you that the new version crashed, timed out or failed under real load. It cannot tell you that it returned a slightly wrong response, because nothing ever reads that response.

Comparing responses needs a component that receives both and compares them. That is a job for the application, outside the mesh. If you need to know whether a new version returns *the same results*, mirroring is not the tool. Weighted routing plus careful observation is.

You now know that a shadow returning `503` to every copy is invisible to the client, and that only the shadow's own access log shows the failure. You also know that the mirror's subset must exist, and that a mirror can target a separate Service. The question still open is how to prove, on a quiet day, that the copies arrive at all.

## Common pitfalls

> [!WARNING]
> - **Mirroring to a subset no `DestinationRule` defines.** No copy is sent, and the client sees nothing wrong.
> - **Expecting the shadow's failures to show at the client.** The proxy throws the response away. A shadow that returns `503` to everything looks exactly like a healthy one from the client's side.
> - **Sharing one Service between stable and shadow pods in production.** Requests that do not pass through the `VirtualService` rule can reach the shadow pods. Give the shadow its own Service.
> - **Expecting mirroring to compare responses.** Nothing reads the shadow's response. Mirroring finds crashes and load problems, never wrong results.
