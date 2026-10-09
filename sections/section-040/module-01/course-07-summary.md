# Summary

Istio sets no HTTP route timeout unless you write one, so a client waits as long as a slow backend takes. The `timeout` field on a `VirtualService` rule sets the longest time a client waits. The client's own sidecar proxy measures it. When the time runs out, that proxy cancels the request and returns `504` itself, and its access log marks the line with the response flag `UT`.

A timeout frees only the client. The receiver keeps working and answers on a connection the client has already closed. To test a timeout, put a delay fault on the service being called and the timeout on the route of the caller. A rule with a `fault` ignores its own `timeout` and `retries`, so a delay and a timeout on the same rule never produce a `504`.

A retry policy makes the client's sidecar proxy send a failed request again before the application sees the failure. `attempts` counts retries after the first try, so `attempts: 3` means up to four requests. `retryOn` lists the failures to retry: `5xx`, the narrower `gateway-error`, an exact code such as `"503"`, and connection problems. The client gets one response, so the proof of retries is in the receiver's access log, and the client's access log marks used-up retries with `URX`.

A rule with no `retries` block still has a default policy: 2 retries, only on connection problems. It does not retry a `503` that the application returns. Only `attempts: 0` switches retries off.

The route timeout covers the first try and every retry together. If it is shorter than `(attempts + 1) × perTryTimeout`, it cuts the retries short and the client gets a `504`, with no configuration error anywhere. A try that runs past `perTryTimeout` counts as a failure and is retried with `retryOn: 5xx`. `istioctl proxy-config routes` shows both settings as Envoy holds them, so you can check the arithmetic before you send a request.

Istio retries any request it is told to, including a `POST`. A retried `POST` repeats its effect, so retry only idempotent requests, for example with a `method` match that gives `GET` retries and everything else `attempts: 0`. Keep `attempts` small, because retries multiply the load on a backend that is already overloaded.

Key facts to remember:

- No route timeout by default; a timeout `504` from the client's own proxy carries `UT`.
- A rule with a `fault` ignores its own `timeout` and `retries`.
- `attempts` counts retries, not requests; Envoy calls it `numRetries`.
- The default retry policy is 2 retries on connection problems; only `attempts: 0` turns retries off.
- `timeout` ≥ `(attempts + 1) × perTryTimeout`.
- Retries plus a timeout that fired show `URX,UT` in the access log.

<!-- astrona:playground:destroy -->
