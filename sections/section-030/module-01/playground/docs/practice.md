# Practice – Load balancing and sticky sessions

An exam-style mission for this playground, astronaut. Start the playground first, then
paste the `count_pods` helper from [the overview](overview.md#the-helper-you-need).
The solution uses it.

Try it on your own first, then open the solution. The solution was run and
checked on the playground cluster.

> Make every request to `httpbin` with the same `x-session-id` header go to
> the same pod.

<details><summary>Solution</summary>

Write the DestinationRule to a file, then apply it.

Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: httpbin, namespace: bookinfo}
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      consistentHash: {httpHeaderName: x-session-id}
```

Apply it:

```bash
kubectl apply -f destinationrule-httpbin.yaml
```

Then check the result:

```bash
count_pods -H "x-session-id: abc" $HOSTNAME_URL     #   8 × one pod
count_pods -H "x-session-id: xyz" $HOSTNAME_URL     #   8 × one (maybe other) pod
```

</details>
