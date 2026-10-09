# Prove Which Proxy Originates TLS

A plain request from the `shuttle` pod now reaches `httpbin.org` over `https://`. The response looks the same whether the egress gateway or the sidecar proxy started the TLS (Transport Layer Security) connection. In this part you prove which proxy did it by reading the configuration of both proxies. On the way you find that every sidecar proxy also received the TLS settings, and you keep them on the egress gateway alone with `exportTo`.

The commands below need five objects applied in your playground: the `ServiceEntry` `httpbin-org`, the `Gateway` `departure-gate`, the `DestinationRule` objects `departure-gate` and `httpbin-org-tls`, and the `VirtualService` `httpbin-org-via-gate` with rule 2 on port `443`. They also need the helper functions `call_httpbin` and `log_shuttle` defined in your terminal.

## Two facts, two proofs

There are two separate facts to prove, and each has its own evidence:

| Fact | Evidence |
| --- | --- |
| The egress gateway was in the path | a new line in **the egress gateway's** access log, with upstream port `443` |
| The egress gateway started TLS | the egress gateway's **cluster** for `httpbin.org` has TLS settings |

A **cluster** is Envoy's name for one destination and the settings to connect to it. When a cluster uses TLS, its configuration holds a **`transportSocket`**: the TLS settings Envoy uses for connections to that destination. You can count it in each proxy.

<!-- astrona:playground:renew -->

Ask both proxies for their cluster for `httpbin.org`, and count the `transportSocket` entries:

```sh
echo -n "gate: "
istioctl proxy-config cluster deploy/istio-egress -n istio-egress --fqdn httpbin.org -o json | grep -c transportSocket
echo -n "shuttle: "
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org -o json | grep -c transportSocket
```

You should see:

```text
gate: 1
shuttle: 1
```

The egress gateway has TLS settings, as expected. But the shuttle's sidecar proxy has them too. Ask the shuttle which `DestinationRule` built its clusters:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org
```

```text
SERVICE FQDN     PORT     SUBSET     DIRECTION     TYPE           DESTINATION RULE
httpbin.org      80       -          outbound      STRICT_DNS     httpbin-org-tls.starfleet
httpbin.org      443      -          outbound      STRICT_DNS     httpbin-org-tls.starfleet
```

The shuttle's clusters were also built from `httpbin-org-tls`. Nothing breaks: rule 1 sends the shuttle's requests to the egress gateway, so the shuttle never uses this cluster. But the TLS settings sit in every sidecar proxy, and you can no longer prove from the configuration which proxy starts TLS.

## Keep the TLS settings on the egress gateway

By default a `DestinationRule` is visible to the **whole mesh**. `istiod` sends it to every proxy that might call the host: the egress gateway, and every sidecar proxy. The field **`exportTo`** limits that. It lists the namespaces whose proxies may use the rule. The egress gateway runs in the namespace `istio-egress`, so that is the only namespace to list.

Save this as `destinationrule-httpbin-org-tls.yaml`, replacing the earlier version:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin-org-tls
  namespace: starfleet
spec:
  host: httpbin.org
  exportTo:
  - istio-egress
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: SIMPLE
        sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin-org-tls.yaml
```

Then count again, and send a request to check that the route still works:

```sh
echo -n "gate: "
istioctl proxy-config cluster deploy/istio-egress -n istio-egress --fqdn httpbin.org -o json | grep -c transportSocket
echo -n "shuttle: "
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org -o json | grep -c transportSocket
call_httpbin
```

You should see:

```text
gate: 1
shuttle: 0
  "url": "https://httpbin.org/get"
200
```

One and zero. The TLS settings are on the egress gateway and nowhere else, and the request still arrives over `https://`. That pair of numbers is the shortest proof that the egress gateway starts TLS.

The shuttle's sidecar proxy has a much simpler job. List the clusters that its route table for port `80` can send to:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 80 -o json | grep '"cluster"'
```

You should see:

```text
                            "cluster": "outbound|80|httpbin-org|istio-egress.istio-egress.svc.cluster.local",
                            "cluster": "outbound|80||istio-egress.istio-egress.svc.cluster.local",
                            "cluster": "PassthroughCluster",
```

The first line is rule 1: port `80`, the egress gateway's Service, the subset `httpbin-org`. For the shuttle's sidecar proxy, this is an ordinary plain HTTP request to a Service inside the cluster. Nothing in its configuration involves TLS.

## TLS settings on the wrong host

The most common mistake is to put the TLS settings on the egress gateway's own Service instead of on `httpbin.org`. That `DestinationRule` is about calls **to the egress gateway**, so the proxy that applies it is the shuttle's sidecar proxy. Save this as `destinationrule-departure-gate-wrong-tls.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: httpbin-org
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 80
      tls:
        mode: SIMPLE
        sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-departure-gate-wrong-tls.yaml
```

Then send a request and read the shuttle's access log:

```sh
call_httpbin
log_shuttle
```

You should see (log line shortened):

```text
503
"GET /get HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end} ... "httpbin.org" "10.244.0.6:80" outbound|80|httpbin-org|istio-egress.istio-egress.svc.cluster.local ...
```

The shuttle's sidecar proxy applied the rule and tried a TLS handshake with port `80` of the egress gateway. The egress gateway expects plain HTTP there, so the handshake fails. The response flag `UF` means the connection to the next hop failed, and `WRONG_VERSION_NUMBER` is the TLS error. The TLS settings went to the proxy that calls the host the rule names, which here is the sidecar proxy.

Put the correct `DestinationRule` back by applying the saved file again:

```sh
kubectl apply -f destinationrule-departure-gate.yaml
```

When the route does not work, check these points in order. Each one points at one object:

1. **Does the egress gateway's access log show the request at all?** If not, the problem is rule 1 or the `Gateway`. Check that `mesh` is in the top-level `gateways`, and that the `Gateway` lists the external host.
2. **Does the egress gateway's line show upstream port `443`?** If it shows port `80`, rule 2 routes to the wrong port.
3. **Does the egress gateway's cluster for the external host have a `transportSocket`?** If not, the TLS `DestinationRule` is missing, names the wrong host, or is exported away from `istio-egress`.
4. **Does the external host report `https://`?** That is the end-to-end proof.

You can now prove from the configuration of both proxies that the egress gateway, and only the egress gateway, starts TLS. You know that `exportTo` keeps the settings there, and that TLS settings on the egress gateway's own Service break the first hop. The open question is what changes when the external server also checks who is calling.

## Common pitfalls

> [!WARNING]
> - **The TLS `DestinationRule` on the egress gateway's own Service.** The sidecar proxy applies it and tries TLS with the egress gateway: `503 URX,UF` with `WRONG_VERSION_NUMBER`. The rule must name the external host.
> - **No `exportTo`.** Every sidecar proxy also gets the TLS settings for the host. Nothing breaks, but you can no longer prove which proxy starts TLS.
> - **`exportTo` without the egress gateway's namespace.** Then the egress gateway itself does not get the rule. It sends the request to port `443` as plain text, and `httpbin.org` answers `400 The plain HTTP request was sent to HTTPS port`.
> - **Looking for TLS settings in the sidecar proxy.** With the route in place, the sidecar proxy only sends plain HTTP to the egress gateway. The egress gateway's cluster holds the TLS settings.

## Your mission: Originate TLS At The Egress Gateway Lab

You can now build the five objects, start TLS at the egress gateway, and prove it from the configuration of both proxies. The lab asks you to do the same for a partner server that only speaks TLS, with a client that only sends plain `http://` and an egress gateway in between that must start TLS for every request.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. The lab uses its own small app and the `demo` install of Istio, so the names differ from your playground: the egress gateway is `istio-egressgateway` in `istio-system`, with the pod label `istio: egressgateway`. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-080-02
astrona start ats-014-playground-080-02
```
