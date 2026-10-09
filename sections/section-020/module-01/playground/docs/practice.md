# Practice: Traffic Shifting (Canary Release)

Your training mission, astronaut: an exam-style task for this module. Start the playground first, and paste the `count_versions` helper from [`overview.md`](overview.md). The solution uses it.

Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Send **10%** of `scout` signals to **v2** and the rest to **v1**. Check it with 40 signals, then with 100.

<details><summary>Solution</summary>

Save this as `virtualservice-scout.yaml`:

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
        subset: v1
      weight: 90
    - destination:
        host: scout
        subset: v2
      weight: 10
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

Then count 40 signals, and then 100:

```sh
count_versions 40
count_versions 100
```

You should see something like:

```text
  36 scout-v1
   4 scout-v2
  93 scout-v1
   7 scout-v2
```

With 40 signals you expect about 4 on v2, and with 100 about 10. Each signal is a separate roll, so your numbers will wobble around those values.

</details>
