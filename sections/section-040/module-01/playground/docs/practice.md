# Practice: Timeouts And Retries

Two exam-style training missions for this playground, astronaut. Start the playground first, and
paste the helper functions from the [overview](overview.md#helper-functions).
The solutions use them. Run the commands from the `playground/` folder.

Try each task on your own first, then open the solution. The solutions were
run and checked on a cluster like this one.

## Task 1: a timeout on the caller

> Make `ratings` answer **3 seconds** late. Then make sure callers of
> `reviews` (all on version v3) get an error after at most **1 second**.

<details><summary>Solution</summary>

The delay goes on `ratings`, the service being called. The time limit goes on
`reviews`, the route the caller uses. They must be two different
VirtualServices, because a route with a `fault` ignores its own `timeout`.

```bash
kubectl apply -f examples/04-timeouts/02-destinationrule-ratings-subsets.yaml
```

Save this as `virtualservice-ratings-and-reviews.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: ratings, namespace: bookinfo}
spec:
  hosts: [ratings]
  http:
  - fault:
      delay: {percentage: {value: 100}, fixedDelay: 3s}
    route:
    - destination: {host: ratings, subset: v1}
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: reviews, namespace: bookinfo}
spec:
  hosts: [reviews]
  http:
  - route:
    - destination: {host: reviews, subset: v3}
    timeout: 1s
```

Apply it:

```bash
kubectl apply -f virtualservice-ratings-and-reviews.yaml
```

Then check the result:

```bash

status_and_time http://reviews:9080/reviews/0   # 504 1.0s
```

</details>

## Task 2: retries on one status code

> Requests to `httpbin` must be retried **at most 2 times**, **only on 503**,
> and each try may take at most **500ms**.

<details><summary>Solution</summary>

Save this as `virtualservice-httpbin-retries.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: httpbin, namespace: bookinfo}
spec:
  hosts: [httpbin]
  http:
  - route:
    - destination: {host: httpbin}
    retries:
      attempts: 2
      perTryTimeout: 500ms
      retryOn: "503"
```

Apply it:

```bash
kubectl apply -f virtualservice-httpbin-retries.yaml
```

Then check the result:

```bash

status_and_time http://httpbin:8000/status/503 ; count_received "status/503"   # 503 → 3 (1 + 2 retries)
status_and_time http://httpbin:8000/status/500 ; count_received "status/500"   # 500 → 1 (not retried)
```

</details>
