# Troubleshoot Top-Level TLS And Double Encryption

TLS (Transport Layer Security) origination can look correct and still fail. This part shows the two most common mistakes. In the first, the `DestinationRule` turns on TLS for every port instead of one. In the second, the application keeps encrypting its own requests. `kubectl apply` accepts both mistakes without any warning, so you must learn to spot them from the symptoms.

The commands below need three objects for the host `httpbin.org` in `starfleet`, all named `httpbin`. They are a `ServiceEntry` with port `80` (`HTTP`) and port `443` (`HTTPS`), a `VirtualService` that routes port `80` to port `443`, and a `DestinationRule` that sets `tls.mode: SIMPLE` and `sni: httpbin.org` for port `443`. Keep their YAML in the files `serviceentry-httpbin.yaml`, `virtualservice-httpbin.yaml` and `destinationrule-httpbin.yaml`. With all three applied, `http://httpbin.org/get` from the shuttle answers `200`.

## TLS on every port

The correct `DestinationRule` puts `tls` under `portLevelSettings` for port `443`. `trafficPolicy` also has a top-level `tls` field. It looks like a shorter way to write the same thing, but it applies to **every** port of the host, so it turns on TLS for port `80` too. Port `80` on httpbin.org speaks plain HTTP. The proxy would start a TLS handshake with a server that does not speak TLS on that port.

<!-- astrona:playground:renew -->

Write the wrong version to its own file, so you can switch back easily. Save this as `destinationrule-httpbin-top-level-tls.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: starfleet
spec:
  host: httpbin.org
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin-top-level-tls.yaml
```

Then check the result. Send a plain HTTP request, and look at how the proxy now connects to port `80`. Each port of `httpbin.org` is an Envoy cluster in the shuttle's proxy, that is, the proxy's group of endpoints for one host and port. A cluster that uses TLS has a **transport socket** named `envoy.transport_sockets.tls`:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/get
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 80 -o json | grep '"name": "envoy.transport_sockets'
```

You should see:

```text
200
            "name": "envoy.transport_sockets.tls",
```

The call still works, because the `VirtualService` moves every request away from port `80`. But the port `80` cluster now has a TLS transport socket: the proxy would use TLS for anything it sends there. The mistake stays hidden as long as the redirect catches every request.

To see the damage, delete the `VirtualService` for a moment, so the request stays on port `80`:

```sh
kubectl delete virtualservice httpbin -n starfleet
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see:

```text
virtualservice.networking.istio.io "httpbin" deleted from starfleet namespace
503
[2026-10-08T22:54:14.312Z] "GET /get HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end} - "TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end" 0 121 798 - "-" "curl/8.11.1" "9de07a8b-23d1-4400-a583-2185cac860ee" "httpbin.org" "32.194.118.12:80" outbound|80||httpbin.org - 54.159.186.149:80 10.244.0.6:55130 - default
```

The proxy answered `503` with the response flag `UF` (upstream connection failure) and the error `WRONG_VERSION_NUMBER`. The proxy started a TLS handshake on port `80`, and the server answered in plain HTTP. With the correct `DestinationRule`, the same call without a `VirtualService` simply goes out as plain HTTP on port `80` and gets `200`.

Now apply the correct `DestinationRule` and the `VirtualService` again:

```sh
kubectl apply -f destinationrule-httpbin.yaml -f virtualservice-httpbin.yaml
```

Then check that the call works and that port `80` is plain again:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/get
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 80 -o json | grep -c '"name": "envoy.transport_sockets.tls'
```

You should see:

```text
200
0
```

`0` means the port `80` cluster has no TLS transport socket. Only port `443` uses TLS.

## The application still calls https://

The first mistake was in the mesh configuration. The second one is in the application. TLS origination expects a plain HTTP request from the application. If the application keeps calling `https://`, it encrypts the request itself, and the proxy encrypts it a second time on port `443`. The server receives a TLS connection inside another TLS connection and cannot read either.

Send an HTTPS request from the shuttle while TLS origination is on, then read the access log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" https://httpbin.org/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see:

```text
000
command terminated with exit code 35
[2026-10-08T22:54:31.738Z] "- - -" 0 - - - "-" 524 272 498 - "-" "-" "-" "-" "32.194.118.12:443" outbound|443||httpbin.org 10.244.0.6:35068 3.225.83.162:443 10.244.0.6:58156 httpbin.org -
```

`curl` exit code `35` means its TLS handshake failed. With `-v`, `curl` names the reason: `packet length too long`, because the answer it received was itself wrapped in TLS. The access log shows `"- - -"`: the proxy could not read the request, so it wrapped the raw bytes in TLS once more. The fix is in the application, not in the mesh: call `http://`.

You can now recognise both mistakes from their symptoms. A top-level `tls` hides behind the redirect and shows up as `503 UF` with `WRONG_VERSION_NUMBER` on port `80`, and `istioctl proxy-config cluster ... --port 80` shows it directly. An application that still calls `https://` fails with `curl` exit code `35`. What is still open is how to prove, beyond a `200`, that the proxy really added TLS.

## Common pitfalls

> [!WARNING]
> - **`tls` at the top of `trafficPolicy`.** It turns on TLS for every port of the host, including the plain port `80`. It hides behind the redirect, and any request that stays on port `80` fails with `503 UF` and `WRONG_VERSION_NUMBER`.
> - **Trusting a `200` as proof that the placement is right.** Check each port's cluster with `istioctl proxy-config cluster ... --port`. Only the port that leaves the pod encrypted should have `envoy.transport_sockets.tls`.
> - **An application that still calls `https://`.** The proxy encrypts a request that is already encrypted, and the handshake fails with `curl` exit code `35`.

## Your mission: Fix A Broken TLS Origination Lab

You can now build TLS origination one object at a time and tell from the symptom which object is wrong. The lab gives you TLS origination to a TLS-only server outside the mesh that fails, and asks you to find and fix the two objects that are wrong.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-070-02-02
astrona start ats-014-playground-070-02
```
