# Fit Retries Inside The Timeout

A route timeout and a retry policy share one time limit. If you size them on their own, the timeout can cut the retries short, and nothing reports an error. This part covers the arithmetic that prevents this, what the mistake looks like, how a per-try timeout turns a slow response into a retry, and how to read both settings from the proxy.

## One timeout for every try

The route `timeout` on a `VirtualService` rule limits the **whole request as the client sees it**. A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and retries. The client's sidecar proxy, the Envoy container that Istio adds to each pod, enforces both. A retry policy on the same rule has `attempts`, the number of retries after the first try, and `perTryTimeout`, the time limit for each single try. Every retry has to fit inside the timeout, not next to it:

```text
  timeout: 5s
  ├───────────────────────────────────────────────────┤

  try 1          retry 1        retry 2        retry 3
  ├── 1s ──┤     ├── 1s ──┤     ├── 1s ──┤     ├── 1s ──┤
                                                        ▲
                                              done after ~4s: fits

  timeout: 1.5s
  ├────────────┤
  try 1          retry 1   ✂ cut off here, the client gets 504
  ├── 1s ──┤     ├── 1s ──┤
```

Check this rule before you write any retry policy:

> **`timeout` ≥ (`attempts` + 1) × `perTryTimeout`**, plus a little room for making the connection.

It is `attempts + 1` because `attempts` counts retries, and there is also the first try. With `attempts: 3` and `perTryTimeout: 1s`, you need at least 4 seconds.

Set `timeout: 1.5s` with that policy, and the request stops soon after the second try starts. The client sees a `504`, the retry policy looks broken, and **nothing reports a configuration error**. Istio did not ignore the policy. The policy ran out of time.

### The timeout cuts the retries short

You can see this happen. The commands below use two helpers. `status_and_time` sends one request from the `shuttle` test pod and prints the status code and the total time. `count_received` waits a moment, then counts the lines that match a text in the access logs of the `probe` pods, an HTTP echo server on port 8000. The access log is the log where each sidecar proxy writes one line per request. Paste both into your terminal:

<!-- astrona:playground:renew -->

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

Now write a policy whose timeout is too short. Save this as `virtualservice-probe-short-budget.yaml`:

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
    timeout: 1.5s
    retries:
      attempts: 3
      perTryTimeout: 1s
      retryOn: 5xx
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-short-budget.yaml
```

Then check the result. Send one request to `/delay/3`, a path that waits 3 seconds before it answers, and count how often it reached the probe:

```sh
status_and_time http://probe:8000/delay/3
count_received "delay/3" 10s
```

You should see:

```text
504 1.502060s
2
```

The sidecar proxy cut off each try after 1 second and sent it again. The policy allowed up to four tries, but the 1.5-second timeout only had room for two. **A `504` where you expected a retried success is the sign of this mistake.**

## Per-try timeouts turn slow responses into retries

The `perTryTimeout` field does more than limit each try. When a try runs past it, the sidecar proxy cancels that try, and the cancelled try counts as a failure. With `retryOn: 5xx`, the proxy retries it. That helps when one pod hangs, because the retry may go to a healthy pod.

Give the route a generous timeout, with 2 retries of 1 second each. Save this as `virtualservice-probe-per-try.yaml`:

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
    timeout: 10s
    retries:
      attempts: 2
      perTryTimeout: 1s
      retryOn: 5xx
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-per-try.yaml
```

Then send one slow request, count it at the probe, and read the `shuttle` access log:

```sh
status_and_time http://probe:8000/delay/3
count_received "delay/3" 12s
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line shortened):

```text
504 3.071110s
3
"GET /delay/3 HTTP/1.1" 504 URX,UT upstream_per_try_timeout ... "probe:8000" ...
```

One try plus two retries, each cut off after 1 second: 3 seconds, then a `504`. The access log shows two response flags together: `UT` (upstream timeout: a timeout fired) and `URX` (upstream retry limit exceeded: the retries are used up).

## Read both settings from the proxy

`istiod`, the Istio control plane, turns your `VirtualService` into Envoy configuration and sends both numbers to the `shuttle` sidecar proxy. Reading them there is the fastest way to check the arithmetic against what the proxy really holds.

Put the short-timeout policy back:

```sh
kubectl apply -f virtualservice-probe-short-budget.yaml
```

Then read the probe's route for port 8000 in the `shuttle` route table:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json \
  | grep -E '"timeout"|retryOn|numRetries|perTryTimeout'
```

You should see (shortened to the probe's route):

```text
"timeout": "1.500s",
    "retryOn": "5xx",
    "numRetries": 3,
    "perTryTimeout": "1s",
```


You can now size a route timeout for a retry policy, recognise a timeout that cut the retries short, and read both settings from the proxy. The open question is which requests should get retries at all, because the proxy repeats any request it is told to repeat.

## Common pitfalls

> [!WARNING]
> - **A `timeout` shorter than `(attempts + 1) × perTryTimeout`.** The retries are cut short and the client gets a `504` with `UT`. Do the multiplication before you apply.
> - **Forgetting that a per-try timeout is retried.** With `retryOn: 5xx`, a try that runs past `perTryTimeout` is retried. The access log then shows `URX,UT`.
> - **Reading `numRetries` as the number of tries.** Envoy's `numRetries` is the `attempts` field: retries after the first try, so add one before you multiply.
