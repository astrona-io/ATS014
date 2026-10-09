# Question

Solve this question on: `terminal`

A partner server in the `outpost` namespace only accepts TLS (Transport Layer Security), and only from callers that present a client certificate it trusts. The `shuttle` pod sends plain `http://`, so the egress gateway, an Envoy proxy at the edge of the mesh that outgoing traffic passes through, must start a mutual TLS handshake for it. All five objects for that route exist, and the partner delivered the client certificate as a `Secret`. Still, every request from the `shuttle` pod fails.

Your cluster has:

* `istio-egress`: the egress gateway, with the Deployment and Service `istio-egress` and pods labelled `istio: egress`.
* `starfleet` (sidecar injection on). It holds the `shuttle` client, the `Secret` `partner-client-cert` (`tls.crt`, `tls.key` and `ca.crt`, delivered by the partner), and five objects for the host `partner.outpost.example`:
  * the `ServiceEntry` `partner` (ports `80` and `443`)
  * the `Gateway` `departure-gate` (port `80`)
  * the `DestinationRule` `departure-gate`, with the empty subset `partner`
  * the `VirtualService` `partner-via-gate`
  * the `DestinationRule` `partner-tls`, with `tls.mode: MUTUAL` and `credentialName: partner-client-cert` for port `443`
* `outpost` (sidecar injection off). It holds the `partner` server, which only listens on port `443` with TLS. It answers with the client certificate it received, for example `client=CN=... verify=SUCCESS`. This lab needs no internet access.

Send a test request with:

```bash
kubectl exec -n starfleet deploy/shuttle -- curl -s -w "\n%{http_code}\n" http://partner.outpost.example/
```

The first response can take up to 30 seconds. There is more than one fault. Find each one with the egress gateway's access log, `istioctl proxy-config` and the `istiod` log, then fix it.

**What the grader checks**

1. `GET http://partner.outpost.example/` from `deploy/shuttle` in `starfleet` returns **200**, and the partner server reports **`verify=SUCCESS`** for the client certificate `CN=starfleet-departure-gate`.
2. The egress gateway's own access log gains a line for that request, with an upstream on port **443**.
3. The second rule of `partner-via-gate` (the rule for the `departure-gate` gateway) routes to `partner.outpost.example` on port **443**. The first rule still matches `mesh` and routes to the egress gateway's Service.
4. The egress gateway has loaded `kubernetes://partner-client-cert` (status `ACTIVE` in `istioctl proxy-config secret`), from a `Secret` with `tls.crt`, `tls.key` and `ca.crt`.
5. The shuttle's sidecar proxy has no TLS settings and no certificate for the partner.

**What must not change**

* Keep the object names. Do not add a second `VirtualService` or `Gateway` in `starfleet`.
* Keep `partner-tls` as it is: host `partner.outpost.example`, `MUTUAL` on port `443`, `credentialName: partner-client-cert`, `exportTo: [istio-egress]`, and no `insecureSkipVerify`.
* Use the delivered client certificate. Leave the partner server and its configuration in `outpost` alone.
