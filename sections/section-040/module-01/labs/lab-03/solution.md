# Solution Walkthrough

Mission debrief, astronaut. The probe's retry policy re-sent every 5xx three times, including the probe's own `500` errors, which fail the same way on every try. The fix is to narrow `retryOn` to the one code worth re-sending, `503`, with two retries that fit their abort window.

---

## Step 1: See the Problem

Read the retry policy and the abort window on the probe's flight plan:

```sh
kubectl get virtualservice probe -n starfleet -o jsonpath='{.spec.http[0].retries}{" "}{.spec.http[0].timeout}{"\n"}'
```

```text
{"attempts":3,"retryOn":"5xx"} 10s
```

Now send one signal to `/status/500` and count how often it reached the probe. The sender always gets just one answer, so only the probe's flight log shows the re-sends:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/500
sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=8s | grep -c "status/500"
```

```text
500 0.049813s
4
```

One `500` reached the probe four times: the first try plus three retries. A bug does not go away when you ask again, so those three retries were only extra load.

---

## Step 2: Retry Only 503

Work out the abort window first. Two retries plus the first try is three tries, and each may take 1 second, so the `timeout` must be at least 3 seconds. `4s` leaves room for making the connection. Save this as `virtualservice-probe.yaml`:

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

---

## Step 3: Prove It

Send one `503`, one `500` and one `502`, and count each at the probe:

```sh
for code in 503 500 502; do
  kubectl exec -n starfleet deploy/shuttle -- \
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/status/$code
  sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=6s | grep -c "status/$code"
  sleep 3
done
```

```text
503 0.063926s
3
500 0.019106s
1
502 0.004942s
1
```

The `503` reached the probe three times: the first try plus two retries. The `500` and the `502` each reached it once.

Then submit:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-03
```

```text
PASS: the probe flight plan retries only 503 (attempts 2, perTryTimeout 1s, timeout 4s); at the probe a 503 arrived 3 times, a 500 and a 502 once each
```

---

## Mistakes That Fail This Mission

- **`retryOn: gateway-error`.** It covers `502`, `503` and `504`, so the `502` is still re-sent.
- **`retryOn: 5xx,503`.** The `5xx` still re-sends every 5xx, including the `500`.
- **`attempts: 3`.** `attempts` counts retries after the first try, so the `503` would reach the probe four times.
- **Removing the `retries` block.** The default policy does not re-send the probe's own `503`, so it would arrive only once.
- **A `timeout` under 3 seconds.** Three tries of 1 second do not fit, so the retries would be cut short.
