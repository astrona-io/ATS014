# Two Ways To Break It

Astronaut, TLS origination can look correct and still fail. This part shows the two most common ways: the seal placed on the wrong port, and an application that keeps sealing its own signals. Both mistakes pass `kubectl apply` without a word.

The commands below need the `httpbin` `ServiceEntry`, `VirtualService` and `DestinationRule` applied in your playground, as the files `serviceentry-httpbin.yaml`, `virtualservice-httpbin.yaml` and `destinationrule-httpbin.yaml`. With all three, `http://httpbin.org/get` from the shuttle answers `200`.

## The seal on every port

The correct `DestinationRule` puts `tls` under `portLevelSettings` for port `443`. `trafficPolicy` also has a top-level `tls` field. It looks like a shorter way to write the same thing, but it applies to **every** port of the host, so it seals port `80` too. Port `80` on httpbin.org speaks plain HTTP, so the proxy would try a TLS handshake with a server that does not speak TLS there.

<!-- astrona:playground:renew -->

### Put tls at the top level

Save the wrong version in its own file, so you can switch back easily. Save this as `destinationrule-httpbin-top-level-tls.yaml`:

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

Then send an open signal, and look at how the proxy now connects to port `80`:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/get
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org --port 80 -o json | grep '"name": "envoy.transport_sockets'
```

You should see:

```text
200
            "name": "envoy.transport_sockets.tls",
```

The call still works, because the flight plan moves every signal away from port `80`. But the port `80` cluster now carries a TLS transport socket: the proxy would seal anything it sends there. The mistake is hidden while the redirect covers every signal.

To see the damage, remove the flight plan for a moment, so the signal stays on port `80`:

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

`503` with the flag `UF` (upstream connection failure) and `WRONG_VERSION_NUMBER`: the proxy started a TLS handshake on port `80`, and the server answered in plain HTTP. With the correct `DestinationRule`, the same call without a flight plan just goes out plain on port `80` and gets `200`.

### Put the right version back

Apply the correct docking instructions and the flight plan again:

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

`0` means the port `80` cluster has no TLS transport socket. Only port `443` is sealed.

## The application still calls https://

Origination expects an open signal from the application. If the application keeps calling `https://`, it seals the signal itself, and the proxy seals it a second time on port `443`. The server receives a sealed crate inside a sealed crate and cannot read either.

### Call https:// with origination switched on

Send a sealed signal from the shuttle, then read the flight log:

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

`curl` exit code `35` means its TLS handshake failed. With `-v`, curl names the reason: `packet length too long`, because the answer it got was itself sealed with TLS. The flight log shows `"- - -"`: the proxy could not read the signal and sealed the raw bytes once more. The fix is in the application, not in the mesh: call `http://`.

## Common pitfalls

> [!WARNING]
> - **`tls` at the top of `trafficPolicy`.** It seals every port of the host, including the open port `80`. It hides behind the redirect, and any signal that stays on port `80` fails with `503 UF` and `WRONG_VERSION_NUMBER`.
> - **Trusting a `200` as proof the placement is right.** Check each port's cluster with `istioctl proxy-config cluster ... --port`. Only the port that leaves the ship should carry `envoy.transport_sockets.tls`.
> - **An application that still calls `https://`.** The proxy seals an already sealed signal, and the handshake fails with `curl` exit code `35`.

> *Seal only the port that leaves the ship, and let the application speak plain HTTP to its own proxy.*

## Your mission: Repair The Sealed Channel Lab

You can now build TLS origination one object at a time and tell from the symptom which object is wrong. Now prove it in a graded mission: a sealed channel to a vault outside the mesh is broken, and you must find and fix the two objects that are wrong.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-02/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-02/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-070-02-02
astrona start ats-014-playground-070-02
```
