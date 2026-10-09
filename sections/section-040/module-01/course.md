# Timeouts And Retries

When one backend stops answering, the client that called it waits with the connection open, and the clients of that client wait too. One slow service can stall a whole chain of calls, and nothing crashes anywhere. Adding more pods does not fix this. A time limit does.

A **timeout** is that time limit: if no response has come back in time, the client's sidecar proxy gives up and returns an error instead of waiting forever. The sidecar proxy is the Envoy container that Istio adds to each pod; all traffic in and out of the pod passes through it. **Retries** handle the other side: many failures last only a moment, so the sidecar proxy can send a failed request again without the application knowing.

Both are fields on a rule of a `VirtualService`, the Istio object that sets how requests to a host are routed. They share one time limit, and that is the detail exams like to test most: the route `timeout` covers the whole request, **including** all retries. A timeout shorter than (`attempts` + 1) × `perTryTimeout` cuts the retries short without any error.

## Learning objectives

After this module you can:

- Set a route `timeout`, say which proxy measures it, and name the status code the client receives.
- Test a timeout by putting a delay fault on the service being called and the timeout on the caller, and explain why the two cannot share one rule.
- Explain why a timeout protects the client but does not stop the receiver's work.
- Configure `retries` with `attempts`, `perTryTimeout` and `retryOn`, and choose between `5xx`, `gateway-error` and an exact status code.
- Read `attempts` correctly as the number of retries *after* the first try.
- State Istio's default retry policy and how to switch retries off for real.
- Calculate the timeout a retry policy needs, and recognise cut-off retries from a `504` with `UT` and used-up retries from `URX`.
- Prove how many tries really happened from the receiver's access log.
- Keep retries away from requests that are not safe to send twice.

## Before you start

This module expects some knowledge of Istio routing, and a playground that is ready before the first hands-on step.

### What you should already know

- **How the mesh works.** A sidecar proxy runs beside every application container, and `istiod`, the Istio control plane, sends it configuration. You can read that configuration with `istioctl proxy-config`.
- **`VirtualService` routing.** How to write a `VirtualService` with routing rules. Both settings in this module are extra fields on such a rule.

### What is in your playground

Your playground is one `kind` cluster with **Istio 1.30.5** installed with Helm. Access logs are switched on, so every sidecar proxy writes one line per request. Everything you need runs in the **`starfleet`** namespace:

| Workload | What it does |
| --- | --- |
| `bridge`, `cargo` | Web frontend on port `9080` and the backend that returns item details |
| `scout` v1, v2, v3 | Backend in three versions on port `9080`. Only v2 and v3 call `navcom` |
| `navcom` | Backend that `scout` v2 and v3 call for a rating |
| `probe` v1, v2 | HTTP echo server on Service port `8000` that fails on request. `/delay/<seconds>` waits before it answers, `/status/<code>` answers with exactly that status code, and `/status/200,503` picks one of the two at random |
| `shuttle` | Test client pod; you send every test request from here |

A `DestinationRule` with the `scout` subsets v1, v2 and v3 is already applied, and so is a `VirtualService` that sends requests with the header `end-user: jason` to `scout` v2. There is **no** timeout and **no** retry rule yet. You write them in this module.

Start your playground now, and keep it running while you read the parts:

<!-- astrona:playground -->

The playground guide ends with two exam-style practice tasks with checked solutions, for when you want more practice.

## The order of the parts

The module has four parts, a lab after each of the last three parts, and a summary at the end.

The first part shows that Istio sets no route timeout by default, how to set one, and how to find the `UT` response flag in the access log. The second part tests a timeout across two services with a delay fault, shows that the receiver keeps working, and shows why a delay and a timeout on the same rule never fire. Its lab asks you to move a timeout off a rule with a fault.

The third part configures retries with `attempts`, `perTryTimeout` and `retryOn`, counts the retries at the receiver, and shows the default retry policy and how to switch it off. Its lab asks you to narrow a retry policy to one status code.

The fourth part fits the retries inside the route timeout, reads both settings from the proxy, and keeps retries away from requests that are not safe to repeat. Its lab asks you to give a write path no retries and a read path retries that fit inside their timeout.
