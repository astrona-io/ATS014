# Practice – Traffic shifting (canary release)

Your training mission, astronaut: an exam-style task for this module. Start the playground first, and paste the
`count_versions` helper from [`overview.md`](overview.md). The solution uses
it.

Try it on your own first, then open the solution. The solution was run and
checked on a cluster like this one.

> Send **10%** of `scout` traffic to **v2** and the rest to **v1**. Check it
> with 40 requests.

<details><summary>Solution</summary>

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: scout, namespace: starfleet}
spec:
  hosts: [scout]
  http:
  - route:
    - destination: {host: scout, subset: v1}
      weight: 90
    - destination: {host: scout, subset: v2}
      weight: 10
```

Apply it:

```bash
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```bash
count_versions 40
#  38 scout-v1
#   2 scout-v2      (about 4 expected – random)
```

</details>
