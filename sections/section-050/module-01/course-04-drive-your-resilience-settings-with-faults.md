# Drive Your Resilience Settings With Faults

Astronaut, a drill on its own only breaks things. Its real job is to prove that your timeouts and retries work **before** a real ship fails. This part shows which drill tests which setting, the one trap that makes a drill silently skip your retries and timeout, and how to find a drill somebody forgot to remove.

## Which drill tests which setting

Each resilience setting answers a different kind of trouble, so each one needs a different drill to prove it:

| You want to prove | Drill to run | What you should see |
| --- | --- | --- |
| A timeout fires | `delay` longer than the timeout | `504` after the timeout, `UT` in the caller's flight log |
| Retries recover from failures | `abort` on part of the signals | Fewer failures than the abort percentage |
| A failing ship is set aside | Neither drill | Nothing: the drill never reaches a ship |

The last row surprises people. Setting a failing ship aside, outlier detection, counts the errors that a **real ship** sends back. An abort is answered by the sender's own communications officer, so no ship ever sent an error, and no ship is ever set aside. To test that setting, you need a ship that really fails.

The middle row has a trap of its own, and it is the next thing to look at.

## The rule that ignores its own retries

A route that carries a `fault` ignores the `retries` and the `timeout` on that **same** route. The drill and the safety settings cannot share one rule. Put them there anyway, and the configuration is accepted without a word, but the safety settings never run.

<!-- astrona:playground:renew -->

### Try to hide an abort with retries

Abort half the signals to navcom, and add three retries to the same route. Save this as `virtualservice-navcom-abort-with-retries.yaml`:

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

Then note the time, send 10 signals, and count how many signals navcom really received since that time. The short pause gives the flight log time to write its last lines:

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

With three retries, almost every signal should have succeeded in the end. Instead, about half still fail. The last number is the proof: navcom received exactly as many signals as there were `200`s. Not one retry was ever sent.

## Make a timeout fire on demand

To test a timeout, put the drill and the timeout on **different** flight plans. The delay goes on the ship you pretend is slow, navcom. The timeout goes on the route of the ship that waits for it. Here the shuttle waits for the scout, and scout v2 waits for navcom:

```mermaid
flowchart LR
    S["shuttle"] -->|"timeout 0.5s"| R["scout v2"]
    R -->|"held 2s"| N["navcom"]
```

The shuttle gives up after half a second. The scout is still waiting for navcom, which is two seconds away.

### Give up on a slow scout

Send every signal to scout v2, and give up after half a second. Save this as `virtualservice-scout-timeout.yaml`:

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

Apply it, and apply the two-second delay on navcom again:

```sh
kubectl apply -f virtualservice-scout-timeout.yaml
kubectl apply -f virtualservice-navcom-delay-2s.yaml
```

Then send one signal to the scout, wait for scout v2 to finish its own two-second wait, and read both flight logs:

```sh
status_and_time http://scout:9080/reviews/0
sleep 3
kubectl logs -n starfleet deploy/scout-v2 -c istio-proxy --tail=3 | grep ratings
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log lines trimmed):

```text
504 0.539831s
"GET /ratings/0 HTTP/1.1" 200 DI via_upstream ... 2025 ... outbound|9080|v1|navcom.starfleet.svc.cluster.local ...
"GET /reviews/0 HTTP/1.1" 504 UT response_timeout ... 502 ... outbound|9080|v2|scout.starfleet.svc.cluster.local ...
```

Both log lines carry the same request ID, so they are the same signal seen from two ships. The shuttle got a `504` after half a second. Its own flight log says why: **`UT`**, "upstream timeout", after 502 milliseconds. Scout v2 kept waiting and got its `200` from navcom two seconds later, with the `DI` flag, long after the shuttle had given up.

### Put the timeout on the drill rule

Now make the mistake on purpose. Put the delay and the timeout on the **same** navcom route. Save this as `virtualservice-navcom-delay-and-timeout.yaml`:

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

Apply it, and remove the scout timeout so only this rule is in play:

```sh
kubectl apply -f virtualservice-navcom-delay-and-timeout.yaml
kubectl delete virtualservice scout -n starfleet
```

Then send one signal straight to navcom:

```sh
status_and_time http://navcom:9080/ratings/0
```

You should see:

```text
200 2.104704s
```

A `200` after two seconds, not a `504` after half a second. The timeout was accepted and ignored. The same rule as for retries: a drill rule does not run its own safety settings.

## Find a drill somebody forgot

A drill left behind looks exactly like a real outage. The signals fail or crawl, and nothing in any ship explains why. Two places show the truth: the `DI` and `FI` flags in the sender's flight log, and the orders inside the sender's communications officer.

### Read the drill from the proxy's orders

Ask scout v2's communications officer for its routes to navcom, and look for the fault filter:

```sh
istioctl proxy-config routes deploy/scout-v2 -n starfleet --name 9080 -o json \
  | grep -i -A12 'envoy.filters.http.fault'
```

You should see (trimmed):

```text
"envoy.filters.http.fault": {
    "@type": "type.googleapis.com/envoy.extensions.filters.http.fault.v3.HTTPFault",
    "delay": {
        "fixedDelay": "2s",
        "percentage": {
            "numerator": 1000000,
            "denominator": "MILLION"
```

That is the drill as the proxy carries it out. 100% is written as one million out of a million. The block sits under the key `envoy.filters.http.fault`. Search for the word `fault` on its own and you also match ordinary text, so search for the full key.

When you are done, remove every flight plan in the namespace. The playground starts with none:

```sh
kubectl delete virtualservice --all -n starfleet
```

> [!TIP]
> When signals fail or crawl and nobody changed a ship, run `kubectl get virtualservice -A` and search the flight logs for `DI` or `FI` before you open any app logs. A forgotten drill is the cheapest explanation to rule out.

## Common pitfalls

> [!WARNING]
> - **Putting retries or a timeout on the drill rule.** They are ignored without a warning. Put them on the caller's route.
> - **Testing outlier detection with an abort.** The abort never reaches a ship, so no ship is ever set aside.
> - **Reading a drill-made `5xx` as a broken ship.** Check the flight log for `FI` first.
> - **Searching the proxy's orders for the word `fault`.** Search for `envoy.filters.http.fault`.
> - **Leaving a drill behind.** Remove it as soon as the test is done. Somebody else will otherwise debug it as an outage.

> *Drills exist to prove your safety settings. Keep them on separate rules, read the flags in the sender's flight log, and remove the drill when the test is done.*

## Your mission: Fault Injection With Delays And Aborts

You can now drive a timeout with a delay, spot the rule that ignores its own retries, and find a drill from the proxy's orders. Now prove it in a graded mission: add a delay and an abort for one test user only, and show how a timeout meets the delay.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-050-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-050/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-050-01
astrona start ats-014-playground-050-01
```
