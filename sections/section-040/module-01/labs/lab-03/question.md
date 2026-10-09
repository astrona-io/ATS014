# Question

Solve this question on: `terminal`

Astronaut, your mission: make the probe's retry policy re-send only the signals that are worth re-sending.

The planet `starfleet` runs:

* `probe` — an echo service, v1 and v2 behind one Service on port 8000. `/status/<code>` answers with exactly that status code.
* `shuttle` — your test client, with `curl`.

The probe's flight plan already has a retry policy: every 5xx is re-sent three times. That includes the probe's own `500` errors, which are bugs that fail the same way on every try. Each one reaches the probe four times.

Change the `VirtualService` named `probe` so that:

1.  It still has exactly **one** rule, routing to the `probe` Service.
2.  Retries happen **only** for the status code **`503`**. No `5xx` and no `gateway-error`.
3.  There are at most **2 retries** after the first try (`attempts: 2`).
4.  Each try may take at most **1 second** (`perTryTimeout`).
5.  The route `timeout` leaves room for every try: at least `(attempts + 1) × perTryTimeout`.

The grader sends one signal at a time from the `shuttle` and counts how often each one reached the probe:

6.  A signal to `/status/503` reaches the probe **3** times.
7.  A signal to `/status/500` reaches the probe exactly **once**.
8.  A signal to `/status/502` reaches the probe exactly **once**.

Leave the Deployments and Services unchanged.
