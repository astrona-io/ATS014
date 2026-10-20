# Solution Walkthrough

The retry policy of the `probe` retried every `5xx` status code three times. That includes the `500` errors of the probe itself. A `500` is usually an application bug, and it fails the same way on every try. The fix is one edit of the `VirtualService`: narrow `retryOn` to the one code that is worth another try, `503`. Items 1 to 5 describe the edited object, and items 6 to 8 prove it with the access log of the probe.

---

## Start: See The Problem

A `VirtualService` is the Istio object that sets how requests to a host are routed, including retries and timeouts. Read the retry policy of the `probe` `VirtualService`:

```sh
kubectl -n starfleet get virtualservice -o name
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http}{"\n"}'
```

```text
virtualservice.networking.istio.io/probe
[{"retries":{"attempts":3,"retryOn":"5xx"},"route":[{"destination":{"host":"probe"}}],"timeout":"10s"}]
```

The policy retries every `5xx` three times, and the route timeout is `10s`. The client always gets just one response, so only the access log of the probe shows the retries. The sidecar proxy of the probe is the Envoy container that Istio adds to each pod, and it writes one log line for each request it receives. Count the lines for `/status/500` before and after one request. Wait before each count, because the proxy writes the line a moment after the request:

```sh
sleep 5
BEFORE=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/500")
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/500
sleep 5
AFTER=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/500")
echo "reached the probe: $((AFTER - BEFORE))"
```

```text
500 0.155987s
reached the probe: 4
```

One `500` reached the probe four times: the first try plus three retries. A bug does not go away when you send the request again, so the three retries were only extra load.

The task also says to leave the Deployments and Services unchanged. Save their identity now, and the `generation` of the `VirtualService`:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
generation=1
NAME       REPLICAS   UID
probe-v1   1          519a0876-b75d-4a1d-b9fe-b1ebba23beb7
probe-v2   1          c79e05dc-f3ab-407a-acef-a0411526f10c
{"app":"probe"} 8000
```

---

## Items 1 To 5: Rewrite The Retry Policy

> **Task item 1:** It still has exactly **one** rule, routing to the `probe` Service.
>
> **Task item 2:** Retries happen **only** for the status code **`503`**. No `5xx` and no `gateway-error`.
>
> **Task item 3:** There are at most **2 retries** after the first try (`attempts: 2`).
>
> **Task item 4:** Each try may take at most **1 second** (`perTryTimeout`).
>
> **Task item 5:** The route `timeout` leaves room for every try: at least `(attempts + 1) × perTryTimeout`.

The five items describe one rule, so you write the object once. First do the arithmetic for item 5. `attempts: 2` means two retries after the first try, so there are three tries. Each try may take 1 second:

```text
attempts: 2   ->  2 retries + 1 original try  =  3 tries
3 tries x 1s perTryTimeout                    =  3s minimum
plus headroom for connection setup            ->  use 4s
```

So the route `timeout` is `4s`. Write `retryOn` as the string `"503"`. The quotes matter: they keep YAML from reading it as a number. Save this as `virtualservice-probe.yaml`:

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
    timeout: 4s
    retries:
      attempts: 2
      perTryTimeout: 1s
      retryOn: "503"
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

```text
virtualservice.networking.istio.io/probe configured
```

Check item 1. List the `VirtualService` objects, and print the destination hosts of all rules:

```sh
kubectl -n starfleet get virtualservice -o name
kubectl -n starfleet get virtualservice probe -o jsonpath='rules={@.spec.http[*].route[*].destination.host}{"\n"}'
```

```text
virtualservice.networking.istio.io/probe
rules=probe
```

There is one `VirtualService`, with one rule that routes to `probe`. Check items 2 to 5. Print the retry policy and the timeout:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http[0].retries} timeout={.spec.http[0].timeout}{"\n"}'
```

```text
{"attempts":2,"perTryTimeout":"1s","retryOn":"503"} timeout=4s
```

The policy retries only `503`, with 2 retries and a per-try timeout of `1s`. The timeout of `4s` is at least `(2 + 1) × 1s = 3s`.

---

## Item 6: A `503` Reaches The Probe Three Times

> **Task item 6:** A request to `/status/503` reaches the probe **3** times.

Send one request to `/status/503`, and count it at the probe. `istiod`, the Istio control plane, sends the new policy to the proxy. If the count is still 4 or 1, wait a few seconds and try again:

```sh
sleep 5
BEFORE=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/503")
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/503
sleep 5
AFTER=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/503")
echo "reached the probe: $((AFTER - BEFORE))"
```

```text
503 0.078906s
reached the probe: 3
```

The `503` reached the probe three times: the first try plus two retries. The client still got a `503`, because `/status/503` fails every time.

---

## Item 7: A `500` Reaches The Probe Once

> **Task item 7:** A request to `/status/500` reaches the probe exactly **once**.

```sh
sleep 5
BEFORE=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/500")
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/500
sleep 5
AFTER=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/500")
echo "reached the probe: $((AFTER - BEFORE))"
```

```text
500 0.006380s
reached the probe: 1
```

The `500` reached the probe once. Before the fix, the same request reached it four times.

---

## Item 8: A `502` Reaches The Probe Once

> **Task item 8:** A request to `/status/502` reaches the probe exactly **once**.

```sh
sleep 5
BEFORE=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/502")
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/502
sleep 5
AFTER=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c "status/502")
echo "reached the probe: $((AFTER - BEFORE))"
```

```text
502 0.008710s
reached the probe: 1
```

The `502` reached the probe once. With `retryOn: gateway-error`, it would have been retried, because that setting covers `502`, `503` and `504`.

---

## Last Requirement: Nothing Else Changed

> **Task requirement:** Leave the Deployments and Services unchanged.

Run the three commands from the Start section again:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
generation=2
NAME       REPLICAS   UID
probe-v1   1          519a0876-b75d-4a1d-b9fe-b1ebba23beb7
probe-v2   1          c79e05dc-f3ab-407a-acef-a0411526f10c
{"app":"probe"} 8000
```

The `generation` of the `VirtualService` went from `1` to `2`, because you edited it once. The Deployments have the same `UID` values, and the Service is the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-03
```

The grader sends one request at a time from `shuttle` and counts how often each one reaches the probe.

---

## Mistakes That Fail The Grader

- **`retryOn: gateway-error` (item 2).** It covers `502`, `503` and `504`, so the `502` is still retried.
- **`retryOn: 5xx,503` (item 2).** The `5xx` still retries every `5xx` code, including the `500`.
- **`attempts: 3` (item 3).** `attempts` counts retries after the first try, so the `503` would reach the probe four times.
- **Removing the `retries` block (items 2 and 6).** The default policy retries only connection problems, not a `503` from the probe, so the `503` would arrive only once.
- **A `timeout` under 3 seconds (item 5).** Three tries of 1 second do not fit, so the timeout cuts the retries short.
