# Solution Walkthrough

The connection pool limits were never the problem. The retry policy in the `VirtualService` sent every `503` from the `probe` back to it five more times. The fix keeps retries for requests that never reached the `probe`, and stops retrying the `probe`'s own failures.

## Step 1: Read the starting state

List the Istio objects, then print the retry policy of the `VirtualService`:

```sh
kubectl get destinationrule,virtualservice -n starfleet
kubectl get virtualservice probe -n starfleet -o jsonpath='{.spec.http[0].retries}'; echo
```

```text
NAME                                        HOST    AGE
destinationrule.networking.istio.io/probe   probe   14s

NAME                                       GATEWAYS   HOSTS       AGE
virtualservice.networking.istio.io/probe              ["probe"]   14s
{"attempts":5,"perTryTimeout":"1s","retryOn":"5xx"}
```

`retryOn: 5xx` retries every `5xx` answer, and `attempts: 5` allows five more tries per request.

## Step 2: Measure the extra load

This helper counts how many `/status/503` requests have arrived at the `probe` pods so far. It reads the `inbound` lines in the access logs of their sidecar proxies:

```sh
probe_received() { t=0; for p in $(kubectl get pod -n starfleet -l app=probe -o name); do
  n=$(kubectl logs -n starfleet $p -c istio-proxy | grep -c '"GET /status/503 HTTP/1.1".*inbound|'); t=$((t+n)); done; echo $t; }
```

Send 5 failing requests from the `shuttle` pod, and count what arrived:

```sh
BEFORE=$(probe_received)
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/status/503; done; echo'
sleep 3
echo "the probe received: $(( $(probe_received) - BEFORE ))"
```

```text
503 503 503 503 503 
the probe received: 30
```

Five requests caused thirty arrivals: the `shuttle` proxy sent each failing request once and retried it five times. Every retry still failed, so the client got nothing for the extra work.

## Step 3: Fix the retry policy

Retry only what never reached the `probe`. Save this as `virtualservice-probe.yaml`:

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
      attempts: 2
      perTryTimeout: 1s
      retryOn: connect-failure,refused-stream
    timeout: 10s
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

```text
virtualservice.networking.istio.io/probe configured
```

`connect-failure` retries a request whose connection could not be opened. `refused-stream` retries a request that the server refused before it read it. Neither covers a `503` that the `probe` sent back.

## Step 4: Check that the shuttle proxy has the new configuration

`istiod` sends the new retry policy to every client proxy. Print the retry policy in the `shuttle` proxy's route for port `8000`:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json | grep -A3 '"retryPolicy"'
```

```text
                            "retryPolicy": {
                                "retryOn": "connect-failure,refused-stream",
                                "numRetries": 2,
                                "perTryTimeout": "1s",
```

## Step 5: Measure again

Send the same 5 failing requests:

```sh
BEFORE=$(probe_received)
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/status/503; done; echo'
sleep 3
echo "the probe received: $(( $(probe_received) - BEFORE ))"
```

```text
503 503 503 503 503 
the probe received: 5
```

Five requests caused five arrivals. The `probe` still answers `503`, but the client proxy no longer sends any failure to it twice.

## Step 6: Submit

```sh
astrona submit -c sections/section-040/module-02/labs/lab-02
```

```text
PASS: the shields are unchanged, the flight plan retries only connection failures (attempts=2, retryOn=connect-failure,refused-stream), and 5 failing signals reached the probe exactly 5 times
```

The grader's message uses older names: "the shields" is the `DestinationRule`, "the flight plan" is the `VirtualService`, and "signals" are requests.

## Common mistakes

- **Swapping `5xx` for `gateway-error`.** `gateway-error` covers `502`, `503` and `504`, so the client proxy still retries the `probe`'s `503`s. The grader fails with "retryOn still contains 'gateway-error'".
- **Only lowering `attempts`.** With `retryOn: 5xx` and `attempts: 2`, each failure still reaches the `probe` three times.
- **Removing the retry policy.** It stops the extra load, but requests that never reached the `probe` lose their second try. The task keeps `connect-failure`.
- **Changing the `DestinationRule`.** Its connection pool limits are correct. Loosening them does not stop retries.
- **Adding a second `VirtualService`.** Two `VirtualService` objects for one host have no defined order when Istio merges them. Change the existing one.
