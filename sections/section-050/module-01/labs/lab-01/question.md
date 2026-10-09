# Question

Solve this question on: `terminal`

The namespace `fault-demo` holds a call chain with two hops:

```text
tester  →  booking-service  →  notification-service
```

* `booking-service`: a Service on port `80`. On every `POST /book` it calls `notification-service`, and it copies the request headers onto that call.
* `notification-service`: a Service on port `80`, the service that `booking-service` depends on.
* `tester`: a client Deployment with `curl`. Send your test requests from it, for example
  `kubectl -n fault-demo exec deploy/tester -- curl -s -X POST http://booking-service/book`

Istio is installed with access logs switched on, all three workloads have a sidecar proxy, and there is no `VirtualService`.

Other teams use this namespace, so your fault test must not change their requests.

Create **two** `VirtualService` objects.

**A `VirtualService` named `notification` for host `notification-service`**, with exactly **two** `http` rules, in this order:

**Rule 1: the scoped fault**

1.  Matches the header **`end-user: tester`**.
2.  Injects **both**:
    *   a `delay` with `fixedDelay` **`7s`** at **100%**
    *   an `abort` with `httpStatus` **`500`** at **100%**
3.  Routes to `notification-service`.

**Rule 2: every other request**

4.  No `match` block. Routes to `notification-service` with no fault and no timeout.

**A `VirtualService` named `booking` for host `booking-service`**

5.  One rule, no `match`, `timeout` **`3s`**, routing to `booking-service`.

The timeout goes on `booking`, not next to the fault, for this reason. In the sidecar proxy, the fault filter holds the request **before** the router starts the request to the destination. A `timeout` on the same rule belongs to the router, so it never sees the delay, and the request waits the full 7 seconds. A timeout only cuts an injected delay short when a **different** proxy enforces it, one hop earlier. Here the proxy of `booking-service` applies the delay on its call to `notification-service`, and the proxy of `tester` enforces the 3-second timeout on its call to `booking-service`.

**What the grader checks**

6.  A `POST /book` with `end-user: tester` does **not** return `200`, and returns after about **3 seconds**: the 7-second delay runs into the 3-second timeout one hop earlier, so the timeout fires before the abort would.
7.  A `POST /book` with **no** header returns **200** in well under a second, five times in a row. A fault without a `match` fails this check.
8.  The access log of the `tester` sidecar proxy has a `504 UT` line (UT: upstream request timeout): the injected delay really made the route timeout fire.
9.  The fault appears in the route configuration of the `booking-service` proxy, which shows that the client's proxy applies it.
10. The fault is on the `VirtualService` for **`notification-service`**, not for `booking-service`. The `booking` `VirtualService` has the timeout and no fault.
