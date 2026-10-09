# Question

Solve this question on: `terminal`

One service has a read path and a write path, and they need different timeout and retry settings: reads are safe to retry, writes are not.

The `resilience-demo` namespace runs one backend and one client:

* `httpbin` — an HTTP echo service on port 8000. `/delay/<seconds>` waits before it answers; `/status/<code>` returns that status code at once.
* `tester` — a client pod with `curl`.

Istio is installed, and both pods have a sidecar proxy (the Envoy container that Istio adds to each pod). There is no `VirtualService`, so there is no route timeout at all.

Create a `VirtualService` named `httpbin` for host `httpbin` with exactly **two** `http` rules, in this order:

**Rule 1 — the write path**

1.  Matches requests whose method is **`POST`**.
2.  Routes to `httpbin` on port 8000.
3.  Sets `timeout` to **`3s`**.
4.  **Switches retries off.** A retried `POST` repeats whatever the first one did, so exactly one request must reach the server per client call. Leaving the `retries` block out does *not* do this.

**Rule 2 — the read path**

5.  Has no `match` block. It is the catch-all rule, so it must come second.
6.  Routes to `httpbin` on port 8000.
7.  Retries with **`attempts: 3`**, **`perTryTimeout: 1s`**, and `retryOn` set to **`gateway-error`**.
8.  Sets a `timeout` large enough that all four tries can run. Work it out rather than guessing: `attempts` counts retries *after* the first try, and the route timeout covers every try together. A timeout that cuts the retries short fails this task.

**What the grader checks**

9.  The `tester` sidecar proxy holds the retry policy (`numRetries` appears in its route configuration).
10. A `GET http://httpbin:8000/status/503` produces **4** requests at the server: the first try plus three retries.
11. A `POST http://httpbin:8000/status/503` produces exactly **1** request at the server.
12. A `GET http://httpbin:8000/delay/10` returns **504**, and takes about as long as the read timeout you configured. This proves that the timeout fires, and that the retries are not cut short earlier.
13. The read rule's `timeout` is at least `(attempts + 1) × perTryTimeout`.
