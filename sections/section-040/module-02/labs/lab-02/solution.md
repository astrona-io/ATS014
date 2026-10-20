# Solution Walkthrough

The connection pool limits were never the problem. The retry policy in the `VirtualService` sent every `503` of the `probe` back to it five more times. The fix keeps retries for requests that never reached the `probe`, and stops retrying the own failures of the `probe`. The Start section shows the extra load. Items 1 to 4 describe the repaired retry policy, and items 5 to 7 prove the result.

---

## Start: Measure The Extra Load

A `VirtualService` is the Istio object that sets how requests to a host are routed, including retries. A `DestinationRule` holds the policies for traffic to a host, including the connection pool. Look at both objects, and print the retry policy:

```sh
kubectl -n starfleet get destinationrule,virtualservice
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http[0].retries}{"\n"}'
```

```text
NAME                                        HOST    AGE
destinationrule.networking.istio.io/probe   probe   1s

NAME                                       GATEWAYS   HOSTS       AGE
virtualservice.networking.istio.io/probe              ["probe"]   1s
{"attempts":5,"perTryTimeout":"1s","retryOn":"5xx"}
```

`retryOn: 5xx` retries every `5xx` answer, and `attempts: 5` allows five more tries for each request. Now count how many requests reach the probe pods. The sidecar proxy of a pod is the Envoy container that Istio adds to the pod, and it writes one access log line for each request. This helper counts the inbound lines for `/status/503` in the logs of all probe pods. It waits first, because the proxy writes the line a moment after the request:

```sh
probe_received() {
  sleep 4; t=0
  for p in $(kubectl get pod -n starfleet -l app=probe -o name); do
    c=$(kubectl logs -n starfleet $p -c istio-proxy | grep -c '"GET /status/503 HTTP/1.1".*inbound|')
    t=$((t+c))
  done
  echo $t
}
```

Send 5 failing requests from the `shuttle` pod, and count what arrived:

```sh
BEFORE=$(probe_received)
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/status/503; done; echo'
AFTER=$(probe_received)
echo "the probe received: $((AFTER - BEFORE))"
```

```text
503 503 503 503 503 
the probe received: 30
```

Five requests caused thirty arrivals: the sidecar proxy of `shuttle` sent each failing request once and retried it five times. Every retry failed too, so the client got nothing for the extra work.

The task says to leave the `DestinationRule`, the Deployments and the Service unchanged. Save their identity now. Item 7 compares against it:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
generation=1
{"connectionPool":{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}}}
NAME       REPLICAS   UID
probe-v1   1          176e03c6-7b47-4017-8860-ea788c16707b
probe-v2   1          2419392d-37b7-4899-95cf-28bc472744c6
shuttle    1          b3896b0b-8aa0-47d0-9726-48ba648c98a1
{"app":"probe"} 8000
```

---

## Items 1 To 4: Repair The Retry Policy

> **Task item 1:** The `VirtualService` named `probe` in `starfleet` still routes every request to the `probe` Service and **still has a retry policy**.
>
> **Task item 2:** `retries.attempts` is **1 or 2**.
>
> **Task item 3:** `retries.retryOn` includes **`connect-failure`**, so requests that never reached the probe still get another try.
>
> **Task item 4:** `retries.retryOn` does **not** retry the probe's own `5xx` answers: it contains none of `5xx`, `gateway-error`, `retriable-status-codes` or `503`.

The four items describe one retry policy, so you write it once. Keep retries for requests that never reached the `probe`, and stop retrying its own failures. `connect-failure` retries a request whose connection could not be opened. `refused-stream` retries a request that the server refused before it read it. Neither covers a `503` that the `probe` sent back. Use `attempts: 2`. Save this as `virtualservice-probe.yaml`:

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

Check item 1. Print the destination host and the retry policy:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http[0].route[0].destination.host} retries={.spec.http[0].retries}{"\n"}'
```

```text
probe retries={"attempts":2,"perTryTimeout":"1s","retryOn":"connect-failure,refused-stream"}
```

The rule routes to `probe` and still has a retry policy. Check items 2 to 4. Print the two fields from the object, and then read the policy that the sidecar proxy of `shuttle` holds. `istiod`, the Istio control plane, sends the policy to the proxy. Wait a few seconds first:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='attempts={.spec.http[0].retries.attempts} retryOn={.spec.http[0].retries.retryOn}{"\n"}'
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json | grep -A3 '"retryPolicy"'
```

```text
attempts=2 retryOn=connect-failure,refused-stream
                            "retryPolicy": {
                                "retryOn": "connect-failure,refused-stream",
                                "numRetries": 2,
                                "perTryTimeout": "1s",
```

Item 2: `attempts` is `2`. Item 3: `retryOn` contains `connect-failure`. Item 4: `retryOn` has none of `5xx`, `gateway-error`, `retriable-status-codes` or `503`. The proxy holds the same policy. `numRetries` is the name that Envoy uses for `attempts`.

---

## Item 5: Five Failing Requests Reach The Probe Five Times

> **Task item 5:** When the `shuttle` sends 5 requests to `http://probe:8000/status/503`, all 5 are answered with `503`, and the probe pods receive **exactly 5** requests, not one more.

Send the same 5 failing requests as in the Start section. Use the helper `probe_received` again:

```sh
BEFORE=$(probe_received)
kubectl -n starfleet exec deploy/shuttle -- sh -c \
  'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/status/503; done; echo'
AFTER=$(probe_received)
echo "the probe received: $((AFTER - BEFORE))"
```

```text
503 503 503 503 503 
the probe received: 5
```

All 5 requests got `503`, and the probe received exactly 5 requests. The Start section showed 30. The `probe` still answers `503`, but the proxy of the client no longer sends any failure to it twice.

---

## Item 6: Exactly One `VirtualService`

> **Task item 6:** There is exactly one `VirtualService` for the probe.

```sh
kubectl -n starfleet get virtualservice -o name
```

```text
virtualservice.networking.istio.io/probe
```

One `VirtualService` exists. Two objects for one host have no defined order when Istio merges them, so always change the existing one.

---

## Item 7: Nothing Else Changed

> **Task item 7:** The `DestinationRule` named `probe` is **left unchanged**. Leave the Deployments and the Service unchanged, and do not add or remove workloads: `starfleet` must keep exactly its 3 Deployments.

Run the four commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
generation=1
{"connectionPool":{"http":{"http1MaxPendingRequests":1,"maxRequestsPerConnection":1},"tcp":{"maxConnections":1}}}
NAME       REPLICAS   UID
probe-v1   1          176e03c6-7b47-4017-8860-ea788c16707b
probe-v2   1          2419392d-37b7-4899-95cf-28bc472744c6
shuttle    1          b3896b0b-8aa0-47d0-9726-48ba648c98a1
{"app":"probe"} 8000
```

The output is the same as before. The `DestinationRule` still has `generation=1` and the same connection pool. The same three Deployments exist with the same `UID` values.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-02/labs/lab-02
```

The grader counts the requests that arrive at the probe pods in the access logs of their proxies.

---

## Mistakes That Fail The Grader

- **Swapping `5xx` for `gateway-error` (item 4).** `gateway-error` covers `502`, `503` and `504`, so the proxy of the client still retries the `503` of the `probe`.
- **Only lowering `attempts` (items 4 and 5).** With `retryOn: 5xx` and `attempts: 2`, each failure still reaches the `probe` three times.
- **Removing the retry policy (items 1 and 3).** It stops the extra load, but requests that never reached the `probe` lose their second try. The task keeps `connect-failure`.
- **Changing the `DestinationRule` (item 7).** Its connection pool limits are correct. Loosening them does not stop retries.
- **Adding a second `VirtualService` (item 6).** Two objects for one host have no defined order. Change the existing one.
