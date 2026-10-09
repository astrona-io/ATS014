# Test Timeouts And Retries With Fault Injection

A fault on its own only breaks things. Its real job is to prove that your timeouts and retries work **before** a real service fails. This part shows which fault tests which setting, the trap that makes a rule silently skip its own retries and timeout, and how to find a fault that somebody forgot to remove.

## Which fault tests which setting

Each resilience setting handles a different kind of trouble, so each one needs a different fault to prove it. A **timeout** is the longest time the client's sidecar proxy (Envoy) waits for a response. **Retries** make the proxy send a failed request again. **Outlier detection** is a `DestinationRule` setting that removes a pod from load balancing after it returns too many errors.

| You want to prove | Fault to inject | What you should see |
| --- | --- | --- |
| A timeout fires | `delay` longer than the timeout | `504` after the timeout, `UT` in the client's access log |
| Retries recover from failures | `abort` on part of the requests | Fewer failures than the abort percentage |
| Outlier detection removes a failing pod | Neither fault | Nothing: the fault never reaches a pod |

The last row surprises people. Outlier detection counts the errors that a **real pod** sends back. An abort is answered by the client's own sidecar proxy, so no pod ever sent an error, and no pod is ever removed. To test outlier detection, you need a pod that really fails.

The middle row has a trap of its own, and it is the next thing to look at.

## A fault rule ignores its own retries

A route that carries a `fault` ignores the `retries` and the `timeout` on that **same** route. In Envoy, the fault filter runs before the router, and the router is the part that sends the request, retries it and times it. An abort is answered by the fault filter, so the router never sees a failed attempt to retry. Istio accepts the configuration without a warning, but the retries and the timeout never run.

<!-- astrona:playground:renew -->

Abort half the requests to `navcom`, and add three retries to the same route. Save this as `virtualservice-navcom-abort-with-retries.yaml`:

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
      abort:
        percentage:
          value: 50
        httpStatus: 500
    route:
    - destination:
        host: navcom
        subset: v1
    retries:
      attempts: 3
      retryOn: 5xx
```

Apply it:

```sh
kubectl apply -f virtualservice-navcom-abort-with-retries.yaml
```

Then check the result. Note the time, send 10 requests with the `count_navcom_status` helper function, and count how many requests `navcom` really received since that time. The short pause gives the proxy time to write its last access log lines:

```sh
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
count_navcom_status
sleep 3
kubectl logs -n starfleet deploy/navcom-v1 -c istio-proxy --since-time=$START | grep -c 'GET /ratings/0'
```

You should see something like:

```text
   6 200
   4 500
6
```

With three retries, almost every request should succeed in the end. Instead, about half still fail. The last number is the proof: `navcom` received exactly as many requests as there were `200` responses. The proxy never sent a single retry.

## Make a timeout fire on demand

If the fault and the timeout cannot share a rule, they must live on **different** `VirtualService` objects. The delay goes on the service that should look slow, `navcom`. The timeout goes on the route of the client that waits for it. Here `shuttle` waits for `scout`, and `scout` v2 waits for `navcom`:

```mermaid
flowchart LR
    S["shuttle"] -->|"timeout 0.5s"| R["scout v2"]
    R -->|"held 2s"| N["navcom"]
```

The diagram shows that the `shuttle` proxy gives up after half a second, while `scout` v2 still waits for `navcom`, which is held for two seconds.

Send every request for `scout` to subset `v2`, and give up after half a second. Save this as `virtualservice-scout-timeout.yaml`:

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
  - route:
    - destination:
        host: scout
        subset: v2
    timeout: 0.5s
```

Apply it. The test also needs the two-second delay on `navcom`, saved as `virtualservice-navcom-delay-2s.yaml`, so apply that file again too:

```sh
kubectl apply -f virtualservice-scout-timeout.yaml
kubectl apply -f virtualservice-navcom-delay-2s.yaml
```

Then check the result. Send one request to `scout`, wait for `scout` v2 to finish its own two-second wait, and read both access logs:

```sh
status_and_time http://scout:9080/reviews/0
sleep 3
kubectl logs -n starfleet deploy/scout-v2 -c istio-proxy --tail=3 | grep ratings
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log lines shortened):

```text
504 0.539831s
"GET /ratings/0 HTTP/1.1" 200 DI via_upstream ... 2025 ... outbound|9080|v1|navcom.starfleet.svc.cluster.local ...
"GET /reviews/0 HTTP/1.1" 504 UT response_timeout ... 502 ... outbound|9080|v2|scout.starfleet.svc.cluster.local ...
```

Both log lines carry the same request ID, so they show the same request from two proxies. `shuttle` got a `504` after half a second. Its own access log gives the reason: the response flag **`UT`**, "upstream request timeout", after 502 milliseconds. `scout` v2 kept waiting and got its `200` from `navcom` two seconds later, with the `DI` flag, long after `shuttle` had given up.

Now make the mistake on purpose, to see it once. Put the delay and the timeout on the **same** `navcom` route. Save this as `virtualservice-navcom-delay-and-timeout.yaml`:

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
        fixedDelay: 2s
    route:
    - destination:
        host: navcom
        subset: v1
    timeout: 0.5s
```

Apply it, and delete the `scout` timeout so that only this rule is in play:

```sh
kubectl apply -f virtualservice-navcom-delay-and-timeout.yaml
kubectl delete virtualservice scout -n starfleet
```

Then check the result. Send one request straight to `navcom`:

```sh
status_and_time http://navcom:9080/ratings/0
```

You should see:

```text
200 2.104704s
```

The result is a `200` after two seconds, not a `504` after half a second. Istio accepted the timeout, and the proxy ignored it. It is the same rule as for retries: a rule with a `fault` does not run its own timeout or retries.

## Find a fault that somebody forgot

A fault left behind looks exactly like a real outage. Requests fail or are slow, and nothing in any application explains why. Two places show the truth: the `DI` and `FI` flags in the client's access log, and the route configuration inside the client's sidecar proxy.

`istioctl proxy-config routes` prints the routes that a proxy holds right now. Ask the proxy of `scout` v2 for its routes on port `9080`, and search for the fault filter:

```sh
istioctl proxy-config routes deploy/scout-v2 -n starfleet --name 9080 -o json \
  | grep -i -A12 'envoy.filters.http.fault'
```

You should see (shortened):

```text
"envoy.filters.http.fault": {
    "@type": "type.googleapis.com/envoy.extensions.filters.http.fault.v3.HTTPFault",
    "delay": {
        "fixedDelay": "2s",
        "percentage": {
            "numerator": 1000000,
            "denominator": "MILLION"
```

This is the fault as the proxy applies it. Envoy writes 100% as one million out of a million. The block sits under the key `envoy.filters.http.fault`. If you search for the word `fault` on its own, you also match ordinary text, so search for the full key.

When you are done, delete every `VirtualService` in the namespace. The playground starts with none:

```sh
kubectl delete virtualservice --all -n starfleet
```

> [!TIP]
> When requests fail or are slow and nobody changed an application, run `kubectl get virtualservice -A` and search the access logs for `DI` or `FI` before you open any application logs. A forgotten fault is the cheapest cause to rule out.

You now know which fault tests which setting, that a rule with a `fault` ignores its own `timeout` and `retries`, and how to find a fault in the route configuration of a proxy. The timeout or retry policy you want to test must always sit on the client's route, one hop away from the fault.

## Common pitfalls

> [!WARNING]
> - **Putting retries or a timeout on the fault rule.** The proxy ignores them without a warning. Put them on the client's route.
> - **Testing outlier detection with an abort.** The abort never reaches a pod, so no pod is ever removed.
> - **Reading an injected `5xx` as a broken service.** Check the access log for `FI` first.
> - **Searching the proxy configuration for the word `fault`.** Search for `envoy.filters.http.fault`.
> - **Leaving a fault behind.** Delete it as soon as the test is done. Otherwise somebody else will debug it as an outage.

## Your mission: Trigger A Route Timeout With A Scoped Delay Lab

You can now make a timeout fire with a delay, spot the rule that ignores its own retries and timeout, and find a fault in the proxy configuration. The lab asks you to add a delay and an abort for one test user only, and to put a timeout one hop above the delay so that it fires. The lab uses its own small app (`booking-service` calling `notification-service`, in the `fault-demo` namespace), not the Starfleet.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-050-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-050-01
astrona start ats-014-playground-050-01
```
