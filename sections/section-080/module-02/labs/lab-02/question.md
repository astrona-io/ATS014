# Question

Solve this question on: `terminal`

Astronaut, a partner on the planet `outpost` only accepts sealed signals, and only from callers that show a client certificate it trusts. Your ships send plain `http://`, so the departure gate (the egress gateway) must start the mutual TLS handshake for them. All five objects for that route exist, and the partner's security officer delivered the client certificate. Still, every signal from the shuttle fails.

Your cluster has:

* `istio-egress`: the egress gateway, Deployment and Service `istio-egress`, pods labelled `istio: egress`.
* `starfleet`: injected. It holds the `shuttle` client, the `Secret` `partner-client-cert` (`tls.crt`, `tls.key` and `ca.crt`, delivered by the partner), and five objects for the host `partner.outpost.example`:
  * the `ServiceEntry` `partner` (ports `80` and `443`)
  * the `Gateway` `departure-gate` (port `80`)
  * the `DestinationRule` `departure-gate`, with the empty subset `partner`
  * the `VirtualService` `partner-via-gate`
  * the `DestinationRule` `partner-tls`, with `tls.mode: MUTUAL` and `credentialName: partner-client-cert` for port `443`
* `outpost`: **not** injected. It holds the `partner` server, which only listens on port `443` with TLS. It answers with the client certificate it saw, for example `client=CN=... verify=SUCCESS`. This lab needs no internet access.

Send a test signal with:

```bash
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
```

The first answer can take up to 30 seconds. There is more than one fault. Find each one with the gate's flight log, `istioctl proxy-config` and the `istiod` log, then fix it.

**What the grader checks**

1. `GET http://partner.outpost.example/` from `deploy/shuttle` in `starfleet` returns **200**, and the partner reports **`verify=SUCCESS`** for the client certificate `CN=starfleet-departure-gate`.
2. The egress gateway's own access log gains a line for that signal, with an upstream on port **443**.
3. Stage 2 of `partner-via-gate` routes to `partner.outpost.example` on port **443**.
4. The egress gateway has loaded `kubernetes://partner-client-cert` (status `ACTIVE` in `istioctl proxy-config secret`), from a `Secret` with `tls.crt`, `tls.key` and `ca.crt`.
5. The shuttle's sidecar has no TLS settings and no keys for the partner.

**What must not change**

* Keep the object names. Do not add a second `VirtualService` or `Gateway` in `starfleet`.
* Keep `partner-tls` as it is: `MUTUAL`, `credentialName: partner-client-cert`, `exportTo: [istio-egress]`, and no `insecureSkipVerify`.
* Use the delivered client certificate. Leave the partner in `outpost` alone.
