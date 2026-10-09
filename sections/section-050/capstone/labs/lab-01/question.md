# Question

Solve this question on: `terminal`

The namespace `orders` holds a call chain with two hops, and other teams use it too:

```text
tester  →  booking-service  →  notification-service
```

* `booking-service`: a Service on port `80`. On every `POST /book` it calls `notification-service`, and it copies the request headers onto that call.
* `notification-service`: a Service on port `80`, the service that `booking-service` depends on.
* `tester`: a client Deployment with `curl`. Send your test requests from it, for example
  `kubectl -n orders exec deploy/tester -- curl -s -X POST http://booking-service/book`

Istio is installed with access logs switched on, all three workloads have a sidecar proxy, and there is no `VirtualService`.

You run two fault injection tests against `notification-service` at the same time. Neither test may change the requests of any other client in the namespace.

Create a `VirtualService` named `notification` for host **`notification-service`** with exactly **three** `http` rules, in this order:

**Rule 1: does a retry policy recover from an abort?**

1.  Matches the header **`x-chaos: abort`**.
2.  Injects an `abort` with `httpStatus` **`503`** at **100%**.
3.  Has a retry policy on the **same rule**: `attempts` **2**, `perTryTimeout` **`1s`**, `retryOn` **`gateway-error`**. The configuration is valid, and you will see it do nothing.
4.  Sets `timeout` to **`5s`**, well above the time the retries need, so the timeout does not cut the retries short.
5.  Routes to `notification-service`.

**Rule 2: does a timeout fire when the service is slow?**

6.  Matches the header **`x-chaos: delay`**.
7.  Injects a `delay` with `fixedDelay` **`7s`** at **100%**.
8.  Routes to `notification-service`, with **no** timeout and **no** retries on this rule.

**Rule 3: every other request**

9.  No `match` block, no fault, no timeout, no retries. Routes to `notification-service`.

Then create a second `VirtualService` named **`booking`** for host **`booking-service`**: one rule, no `match`, `timeout` **`2s`**, routing to `booking-service`.

10. The timeout for the delay test goes **there**, one hop before the fault, and not next to it. In the sidecar proxy, the fault filter holds the request before the router starts the request to the destination. A `timeout` on the same rule belongs to the router, so it never sees the delay, and the request waits all seven seconds. Only a timeout that a different proxy enforces (the proxy of `tester`, on its call to `booking-service`) can stop an injected delay early.

**What the grader checks**

11. A request with `x-chaos: abort` fails, and the access log of the `booking-service` proxy shows exactly **1** attempt to `notification-service`, with the response flag **`FI`** (fault injected), not three. The retry policy is configured and still never runs. An injected abort is a response that the fault filter makes itself, and the fault filter sits before the router. So the router never sees a failed attempt to retry. Retries recover from short failures of the destination; an injected abort never reaches the destination.
12. A request with `x-chaos: delay` fails after about **2 seconds**, and the access log of the **`tester`** proxy shows the response flag **`UT`** (upstream request timeout) for `booking-service`.
13. Five requests with **no** `x-chaos` header return **200**, fast.
14. The `VirtualService` is for host `notification-service`, and the faults appear in the route configuration of the `booking-service` proxy.
