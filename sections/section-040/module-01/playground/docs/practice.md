# Practice: Timeouts And Retries

Two exam-style training missions for this playground, astronaut. Start the playground first, and paste the helper functions from the [overview](overview.md#helper-functions). The solutions use them.

Try each task on your own first, then open the solution. The solutions were run and checked on a cluster like this one.

## Task 1: an abort window on the caller

> Make `navcom` answer **3 seconds** late. Then make sure callers of `scout` (all on ship class v3) get an error after at most **1 second**.

<details><summary>Solution</summary>

The delay goes on `navcom`, the ship being called. The abort window goes on `scout`, the route the caller uses. They must be two different flight plans, because a rule with a `fault` ignores its own `timeout`.

The delay drill routes to navcom's subset `v1`, so navcom needs docking instructions first. Save this as `destinationrule-navcom.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: navcom
  namespace: starfleet
spec:
  host: navcom
  subsets:
  - name: v1
    labels:
      version: v1
```

Apply it:

```sh
kubectl apply -f destinationrule-navcom.yaml
```

Now the two flight plans. Save this as `virtualservice-navcom-and-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: navcom
  namespace: starfleet
spec:
  hosts:
  - navcom
  http:
  - fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 3s
    route:
    - destination:
        host: navcom
        subset: v1
---
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
        subset: v3
    timeout: 1s
```

Apply it:

```sh
kubectl apply -f virtualservice-navcom-and-scout.yaml
```

Then check the result:

```sh
status_and_time http://scout:9080/reviews/0
```

You should see:

```text
504 1.004221s
```

The shuttle gave up after one second. Scout v3 called navcom, navcom held the answer for 3 seconds, and the shuttle's own sidecar answered `504` when its abort window ran out.

</details>

## Task 2: retries on one status code

> Signals to `probe` must be retried **at most 2 times**, **only on 503**, and each try may take at most **500ms**.

<details><summary>Solution</summary>

`attempts: 2` gives two retries after the first try. An exact `"503"` in `retryOn` re-sends only that code. Give the route an abort window that fits every try: (2 + 1) × 500ms is 1.5 seconds, so `timeout: 3s` leaves room. Save this as `virtualservice-probe-retry-503-only.yaml`:

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
    timeout: 3s
    retries:
      attempts: 2
      perTryTimeout: 500ms
      retryOn: "503"
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-retry-503-only.yaml
```

Then check the result. Send one `503` and one `500`, and count how often each reached the probe:

```sh
status_and_time http://probe:8000/status/503; count_received "status/503"
status_and_time http://probe:8000/status/500; count_received "status/500"
```

You should see:

```text
503 0.070910s
3
500 0.002687s
1
```

The `503` reached the probe three times: the first try plus two retries. The `500` was not re-sent.

To see how Envoy holds the policy, read the probe's route in the shuttle's route table:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json \
  | grep -E '"timeout"|retryOn|numRetries|perTryTimeout|retriableStatusCodes' -A1
```

You should see (trimmed to the probe's route):

```text
"timeout": "3s",
"retryOn": ",retriable-status-codes",
"numRetries": 2,
"perTryTimeout": "0.500s",
"retriableStatusCodes": [
    503
```

Envoy has no `retryOn` name for one exact code. It turns `"503"` into the condition `retriable-status-codes` with the list `[503]`.

</details>
