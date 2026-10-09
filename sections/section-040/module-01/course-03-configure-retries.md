# Configure Retries

Many failures only last a moment. A pod restarts, a connection drops, or one request reaches a pod that is briefly in trouble. Send the same request again a moment later and it often succeeds. A **retry** is exactly that: the client's sidecar proxy sends a failed request again, before the application ever sees the failure.

A sidecar proxy is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. This part covers the three fields that control retries, the off-by-one in the most important one, how to choose which failures to retry, and the retry policy that runs even when you set none.

## How a retry works

You set retries on a rule of a `VirtualService`, the Istio object that sets how requests to a host are routed. The client's sidecar proxy sends the request. If the response is one of the failures you listed, the proxy sends the same request again, up to `attempts` more times. Only then does it pass the last response to the application. The application sees **one** request and **one** response.

```mermaid
sequenceDiagram
    participant A as shuttle
    participant S as shuttle sidecar
    participant P as probe
    A->>S: GET /status/503
    S->>P: try 1
    P-->>S: 503
    S->>P: retry 1
    P-->>S: 503
    S->>P: retry 2
    P-->>S: 503
    S->>P: retry 3
    P-->>S: 503
    S-->>A: 503, flag URX
```

The diagram shows that with `attempts: 3`, the sidecar proxy sends up to four requests in total: the first try plus three retries.

## The three fields

A retry policy has three fields. This piece of a `VirtualService` shows them (you do not apply it):

```yaml
http:
- route:
  - destination:
      host: probe
  retries:
    attempts: 3
    perTryTimeout: 2s
    retryOn: 5xx,connect-failure,reset
  timeout: 10s
```

- **`attempts`**: how many **retries** happen after the first try fails. `attempts: 3` means up to **four** requests reach the receiver.
- **`perTryTimeout`**: the timeout for each single try, the first one included.
- **`retryOn`**: a comma-separated list of the failures to retry, with no spaces.

Learn the `attempts` off-by-one now. Envoy's own name for the field, `numRetries`, says it more clearly. When a task says "three attempts", decide whether it means three requests (`attempts: 2`) or three retries (`attempts: 3`).

## Which failures `retryOn` retries

The `retryOn` field takes a list of conditions. These are the ones you meet most often:

| Condition | Retries when |
| --- | --- |
| `5xx` | the receiver answered with any 5xx status, or a try ran past its `perTryTimeout` |
| `gateway-error` | narrower: only 502, 503 and 504 |
| `connect-failure` | the connection could not be made |
| `refused-stream` | the receiver refused the stream (HTTP/2) |
| `reset` | the receiver reset the connection before it answered |
| `retriable-4xx` | the receiver answered 409 |
| `"503"` | the response has exactly this status code. Write the number in quotes |

You can mix names and numbers: `retryOn: connect-failure,reset,503`. For each failed try, the sidecar proxy asks three questions in this order:

```mermaid
flowchart TB
    A["a try fails"] --> Q{"matches retryOn?"}
    Q -->|"no"| S["client gets the failure"]
    Q -->|"yes"| B{"retries left?"}
    B -->|"no"| S
    B -->|"yes"| T{"time left?"}
    T -->|"no"| X["504, no more retries"]
    T -->|"yes"| R["retry"]
```

The diagram shows that a retry needs a matching failure, a retry left and time left. The third question matters most: the route `timeout` is one time limit for the first try and every retry together. If it runs out, no retry is sent, however many are left.

Notice what is missing from the table: most **4xx** codes. A `400` or `404` is the client's own mistake, and a retry gets the same response, only slower.

The choice between `5xx` and `gateway-error` also matters. `gateway-error` means "the receiver, or something on the way to it, had a problem". `5xx` also includes `500`, which is an error inside the application itself. A `500` usually fails the same way on every try, so retrying it rarely helps.

## Watch the retries happen

The client cannot see retries, because it gets one response. The proof is at the **receiver**: every try arrives there as its own request, with its own line in the receiver's sidecar proxy access log. In this playground, access logs are switched on, so every sidecar proxy writes one line per request.

The commands below use two helpers. `status_and_time` sends one request from the `shuttle` test pod and prints the status code and the total time. `count_received` waits a moment, then counts the lines that match a text in the access logs of the `probe` pods, an HTTP echo server on port 8000. Paste both into your terminal:

<!-- astrona:playground:renew -->

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

### Four tries for one request

Start with a policy that retries every 5xx up to three times. Save this as `virtualservice-probe-retries.yaml`:

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
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,connect-failure,reset
    timeout: 10s
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-retries.yaml
```

Then check the result. The probe's `/status/503` path always answers `503`. Send one request to it, count how many reached the probe, and read the `shuttle` access log:

```sh
status_and_time http://probe:8000/status/503
count_received "status/503"
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line shortened):

```text
503 0.125604s
4
"GET /status/503 HTTP/1.1" 503 URX via_upstream ... "probe:8000" ...
```

One request from `shuttle`, four requests at the probe: the first try plus three retries. The response flag **`URX`** means "upstream retry limit exceeded": the retries are used up. `shuttle` still got a `503`, because `/status/503` fails on every single try.

### A flaky backend becomes more reliable

That path was broken, not flaky. Retries do nothing for a broken backend except send it more requests. Now try a path that fails only some of the time: `/status/200,503` picks one of the two at random.

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" "http://probe:8000/status/200,503"
done | sort | uniq -c
```

You should see something like:

```text
   9 200
   1 503
```

Without retries, about half of these requests would fail. With three retries, a request only fails when four tries in a row fail, so most of them succeed. Retries make failures rarer. They do not make them impossible.

## Choose which failures to retry

The `retryOn` field decides which failures count. Two choices from the table are worth seeing for yourself.

### Retry only gateway errors

The first choice is `gateway-error`. Save this as `virtualservice-probe-retry-gateway-error.yaml`:

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
    retries:
      attempts: 3
      retryOn: gateway-error
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-retry-gateway-error.yaml
```

Then send a `500` and a `502`, and count each at the probe:

```sh
status_and_time http://probe:8000/status/500; count_received "status/500"
status_and_time http://probe:8000/status/502; count_received "status/502"
```

You should see:

```text
500 0.007943s
1
502 0.145082s
4
```

The application's own `500` reached the probe once: it was not retried. The `502` is a gateway error, so the sidecar proxy retried it three times.

### Retry one exact status code

The second choice is one exact status code. Save this as `virtualservice-probe-retry-503.yaml`:

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
    retries:
      attempts: 3
      retryOn: "503"
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-retry-503.yaml
```

Then send a `503` and a `502`:

```sh
status_and_time http://probe:8000/status/503; count_received "status/503"
status_and_time http://probe:8000/status/502; count_received "status/502"
```

You should see:

```text
503 0.124179s
4
502 0.003489s
1
```

Only the exact code `503` is retried. The `502` now reaches the probe once.

## The retry policy nobody configured

So far every retry came from a policy you wrote. But a rule with no `retries` block still has a retry policy. You can read it in the `shuttle` route table, and prove what it does with the probe.

### See the default policy

First delete the probe's `VirtualService`, so the probe has no rule of yours at all:

```sh
kubectl delete virtualservice probe -n starfleet
```

```text
virtualservice.networking.istio.io "probe" deleted from starfleet namespace
```

`istioctl proxy-config routes` prints the routes that `istiod`, the Istio control plane, has sent to one proxy. Read the retry fields in the `shuttle` route table for port 8000, and send one `503`:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json \
  | grep -E 'retryOn|numRetries'
status_and_time http://probe:8000/status/503; count_received "status/503"
```

You should see (shortened):

```text
"retryOn": "connect-failure,refused-stream,unavailable,cancelled,retriable-status-codes",
"numRetries": 2,
503 0.007382s
1
```

The default is **2 retries**, only for **connection problems**. The list ends with `retriable-status-codes`, but no status codes are given, so no status code is retried. A `503` that the application sends back is a complete HTTP response, so the default policy does **not** retry it: the request reached the probe once.

The default usually helps you: it hides the short connection failures when a pod is moved or restarted. But it explains two surprises:

- **A failing request sometimes takes longer than expected.** The sidecar proxy retried it twice before the application saw the failure.
- **Removing the `retries` block does not switch retries off.** Neither does `retries: {}`.

### Switch retries off for real

Only `attempts: 0` means "never retry". Save this as `virtualservice-probe-no-retries.yaml`:

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
    retries:
      attempts: 0
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-no-retries.yaml
```

Then send one `503`, and run the flaky loop again:

```sh
status_and_time http://probe:8000/status/503; count_received "status/503"
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" "http://probe:8000/status/200,503"
done | sort | uniq -c
```

You should see something like:

```text
503 0.006197s
1
   7 200
   3 503
```

Each request now gets exactly one try, so the flaky path fails about as often as it fails on its own.

You can now write a retry policy, choose which failures it retries, count the retries at the receiver, and switch retries off. The open question is how retries and the route timeout work together, because they share one time limit.

## Common pitfalls

> [!WARNING]
> - **Reading `attempts` as the total number of requests.** It counts retries *after* the first try. `attempts: 3` sends up to four requests.
> - **Expecting the default retries to cover application errors.** The default only covers connection problems. Add `retryOn: 5xx`, `gateway-error` or an exact code.
> - **Believing that removing the `retries` block switches retries off.** The default still retries twice on connection problems. Only `attempts: 0` turns retries off.
> - **Retrying a `500` with `5xx`.** A `500` is usually an application bug that fails the same way every time. `gateway-error` or an exact code skips it.
> - **Looking for retries at the client.** The client gets one response. Count the tries in the receiver's access log, or look for `URX` in the client's access log.
> - **Retrying a broken backend.** Retries help with short failures, not with a backend that is down.

## Your mission: Retry Only One Status Code Lab

You can now set a retry policy, choose which failures it retries, and count the retries at the receiver. In the lab, a policy retries every 5xx, and you must narrow it to the one status code worth another try.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-040-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/module-01/labs/lab-03
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-03
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-040-01-03
astrona start ats-014-playground-040-01
```
