# Practice – Traffic mirroring (shadowing)

Your training mission, astronaut: an exam-style task for this module. Start the playground first, and paste the
helpers from [`overview.md`](overview.md). The solution uses them.

Try it on your own first, then open the solution. The solution was run and
checked on a cluster like this one.

> Send all `probe` traffic to **v1** and mirror **50%** of it to **v2**.

<details><summary>Solution</summary>

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
  subsets:
  - name: v1
    labels: {version: v1}
  - name: v2
    labels: {version: v2}
```

Apply it:

```bash
kubectl apply -f destinationrule-probe.yaml
```

Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: probe, namespace: starfleet}
spec:
  hosts: [probe]
  http:
  - route:
    - destination: {host: probe, subset: v1}
    mirror: {host: probe, subset: v2}
    mirrorPercentage: {value: 50.0}
```

Apply it:

```bash
kubectl apply -f virtualservice-probe.yaml
```

Then check the result:

```bash

mark_start; send_requests 20; count_received
#  20 probe-v1
# probe-v1 received: 20
# probe-v2 received: about 10
```

</details>
