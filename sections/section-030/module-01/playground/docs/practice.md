# Practice: Sticky Sessions

An exam-style mission for this playground, astronaut. Start the playground first, and paste the `count_pods` helper from [the overview](overview.md#the-helper-you-need). The solution uses it.

Try it on your own first, then open the solution. The solution was run and checked on the playground cluster.

> Make every signal to the `probe` that carries the same `x-session-id` header reach the same pod.

<details><summary>Solution</summary>

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-session-id
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send 8 signals for each of two session ids:

```sh
count_pods -H "x-session-id: abc" $HOSTNAME_URL
count_pods -H "x-session-id: xyz" $HOSTNAME_URL
```

One run gave:

```text
   8 "probe-v1-7888d6c6d5-57cqj"
   8 "probe-v2-58767cc46-9srsh"
```

Each session id is pinned to one pod. The two ids may land on the same pod or on different ones; both are correct.

</details>
