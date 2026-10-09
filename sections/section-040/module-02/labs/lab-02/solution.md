# Solution Walkthrough

Mission debrief, astronaut. The shields were never the problem. The flight plan's retry policy sent every `503` from the probe back to it five more times. The fix keeps retries for signals that never reached the probe, and stops retrying the probe's own failures.

## Step 1: Read the starting state

List the Istio objects, then print the flight plan's retry policy:

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

`retryOn: 5xx` retries every `5xx` answer, and `attempts: 5` allows five more tries per signal.

## Step 2: Measure the storm

This helper counts how many `/status/503` signals have arrived at the probe pods so far, from their flight logs:

```sh
probe_received() { t=0; for p in $(kubectl get pod -n starfleet -l app=probe -o name); do
  n=$(kubectl logs -n starfleet $p -c istio-proxy | grep -c '"GET /status/503 HTTP/1.1".*inbound|'); t=$((t+n)); done; echo $t; }
```

Send 5 failing signals from the shuttle, and count what arrived:

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

Five signals, thirty arrivals: each failing signal was sent once and retried five times. Every retry still failed, so the shuttle got nothing for the extra work.

## Step 3: Fix the retry policy

Retry only what never reached the probe. Save this as `virtualservice-probe.yaml`:

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

`connect-failure` retries a signal whose connection could not be opened, and `refused-stream` one the probe refused before reading it. Neither covers a `503` the probe sent back.

## Step 4: Check the shuttle has the new orders

Print the retry policy in the shuttle's route for port `8000`:

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

Send the same 5 failing signals:

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

Five signals, five arrivals. The probe still answers `503`, but no failure is sent to it twice.

## Step 6: Submit

```sh
astrona submit -c sections/section-040/module-02/labs/lab-02
```

```text
PASS: the shields are unchanged, the flight plan retries only connection failures (attempts=2, retryOn=connect-failure,refused-stream), and 5 failing signals reached the probe exactly 5 times
```

## Common mistakes

- **Swapping `5xx` for `gateway-error`.** `gateway-error` covers `502`, `503` and `504`, so the probe's `503`s are still retried. The grader fails with "retryOn still contains 'gateway-error'".
- **Only lowering `attempts`.** With `retryOn: 5xx` and `attempts: 2`, each failure still reaches the probe three times.
- **Removing the retry policy.** It stops the storm, but signals that never reached the probe lose their second try. The task keeps `connect-failure`.
- **Changing the shields.** The `DestinationRule` is correct. Loosening it does not stop retries.
- **Adding a second `VirtualService`.** Two flight plans for one probe have no set order. Change the existing one.
