# Question

Solve this question on: `terminal`

Namespace `resilience-demo` runs one backend and one client:

* `httpbin` — a Service on port 8000. `/delay/<seconds>` sleeps before answering; `/status/<code>` returns that status immediately.
* `tester` — a client pod with `curl`

Istio is installed, both pods are injected, and there is no `VirtualService`, so there is no route timeout at all.

The service is called on both a read path and a write path, and they need different treatment: reads are safe to retry, writes are not.

Create a `VirtualService` named `httpbin` for host `httpbin` with exactly **two** `http` rules, in this order:

**Rule 1 — the write path**

1.  Matches requests whose method is **`POST`**.
2.  Routes to `httpbin` on port 8000.
3.  Sets `timeout` to **`3s`**.
4.  **Disables retries.** A retried `POST` duplicates whatever the first one did, so exactly one request must reach the server per client call. Note that leaving the `retries` block out does *not* do this.

**Rule 2 — the read path**

5.  No `match` block — it is the catch-all default, and must therefore come second.
6.  Routes to `httpbin` on port 8000.
7.  Retries with **`attempts: 3`**, **`perTryTimeout: 1s`**, and `retryOn` set to **`gateway-error`**.
8.  Sets a `timeout` large enough that all four attempts can actually run. Work out the budget rather than guessing: `attempts` counts retries *after* the first try, and the route timeout covers every attempt together. A timeout that truncates the retries fails this task.

**What the grader checks**

9.  A `GET http://httpbin:8000/status/503` produces **4** requests at the server — the original plus three retries.
10. A `POST http://httpbin:8000/status/503` produces exactly **1** request at the server.
11. A `GET http://httpbin:8000/delay/10` returns **504**, and takes at least as long as the read timeout you configured — proving the timeout fires rather than the retries being cut short early.
12. The read rule's `timeout` is at least `(attempts + 1) × perTryTimeout`.
