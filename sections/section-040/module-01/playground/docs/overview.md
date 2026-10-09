# Overview: Timeouts And Retries (Playground)

This is a **playground**, not a lab. The environment starts clean, installs Istio and the Starfleet sample app, and then waits. There is no task, no `astrona submit` and no pass or fail. You can try things, break them, run `astrona destroy` and start over.

## What is in the playground

The playground is a small cluster with Istio and a sample app that can be slow or fail when you ask it to:

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-040-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only. `istiod` is the Istio control plane; it sends configuration to every sidecar proxy, the Envoy container that Istio adds to each pod.
- Access logs switched on for the whole mesh. Every sidecar proxy writes one line per request, with a response flag when something goes wrong. That is how you see timeouts and retries happen.
- The **`starfleet`** namespace, labelled for sidecar injection, with:
  - `bridge`, `cargo`, `navcom`, and `scout` v1, v2 and v3, all on port 9080. Only `scout` v2 and v3 call `navcom`.
  - `probe` v1 and v2 behind one Service on port 8000, an HTTP echo server that fails on request: `/status/503` always answers `503`, `/status/200,503` picks one of the two at random, and `/delay/3` answers after 3 seconds.
  - `shuttle`, the test client pod inside the mesh.
  - A `DestinationRule` with the `scout` subsets v1, v2 and v3, and a `VirtualService` that sends `end-user: jason` to `scout` v2 and every other request to v1.
- The `bridge` page at `http://127.0.0.1:9080/productpage`.
- **No timeout and no retry rule** yet. Only Istio's built-in default retry policy is active.

You need `kubectl` and `istioctl` 1.30.5 on your own machine. `astrona check` tells you which tools are missing.

## Helper functions

Paste these into your terminal once per new terminal window:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

`status_and_time` sends one request from `shuttle` and prints the status code and the total time. `count_received` counts how many requests the `probe` pods really received, from their access logs. That is the only place you can see retries, because the client only ever gets one response.

## Things to try

Each idea below is a small change to a `VirtualService`. Write the YAML to a file, apply it with `kubectl apply -f`, and watch what happens:

- Time `/delay/3` with and without a 1-second `timeout` on the `probe` `VirtualService`, then find the `UT` flag in the `shuttle` access log.
- Make `navcom` slow with a delay fault and give `scout` a short timeout. Then read the `DI` line in the `scout-v2` access log and see that `scout` still waited the full delay.
- Put the delay and the timeout on the same rule, and see that the timeout never fires.
- Send `/status/503` before and after adding `retries`, and count the requests at the probe: 1, then 4.
- Lower the timeout until it cuts off the retries, and check the arithmetic with `istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json`.
- Send a `POST` with retries on, then split the `VirtualService` with a `method` match so only `GET` is retried.

## Start over without a new cluster

Delete every `VirtualService` and `DestinationRule` you added:

```sh
kubectl delete virtualservice probe navcom -n starfleet --ignore-not-found
kubectl delete destinationrule navcom -n starfleet --ignore-not-found
```

Then put the playground's own `scout` `VirtualService` back. Save this as `virtualservice-scout.yaml`:

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
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

## When you are done

```sh
astrona destroy ats-014-playground-040-01
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

These are two exam-style tasks for this playground. They use the helper functions above. Try each task on your own first, then open the solution. The solutions were run and checked on a cluster like this one.

### Task 1: a timeout on the caller

> Make `navcom` answer **3 seconds** late. Then make sure callers of `scout` (all routed to version v3) get an error after at most **1 second**.

<details><summary>Solution</summary>

The delay goes on `navcom`, the service being called. The timeout goes on `scout`, the route the caller uses. They must be two different `VirtualService` objects, because a rule with a `fault` ignores its own `timeout`.

The delay rule routes to the `navcom` subset `v1`, so `navcom` needs a `DestinationRule` that defines the subset first. Save this as `destinationrule-navcom.yaml`:

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

Now the two `VirtualService` objects. Save this as `virtualservice-navcom-and-scout.yaml`:

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

`shuttle` got an error after one second. `scout` v3 called `navcom`, the `scout-v3` sidecar proxy held the request for 3 seconds, and the `shuttle` sidecar proxy returned `504` when its timeout ran out.

</details>

### Task 2: retries on one status code

> Requests to `probe` must be retried **at most 2 times**, **only on 503**, and each try may take at most **500ms**.

<details><summary>Solution</summary>

`attempts: 2` gives two retries after the first try. An exact `"503"` in `retryOn` retries only that code. Give the route a timeout that fits every try: (2 + 1) × 500ms is 1.5 seconds, so `timeout: 3s` leaves room. Save this as `virtualservice-probe-retry-503-only.yaml`:

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

The `503` reached the probe three times: the first try plus two retries. The `500` was not retried.

To see how Envoy holds the policy, read the probe's route in the `shuttle` route table:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json \
  | grep -E '"timeout"|retryOn|numRetries|perTryTimeout|retriableStatusCodes' -A1
```

You should see (shortened to the probe's route):

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
