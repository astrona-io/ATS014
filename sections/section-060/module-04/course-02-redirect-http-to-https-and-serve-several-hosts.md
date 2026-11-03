# Redirect HTTP To HTTPS And Serve Several Hosts

A gateway that serves HTTPS still gets plain HTTP requests: old links, typed addresses and scripts all start with `http://`. If the gateway ignores them, those clients get a refused connection. A better answer is a redirect to the HTTPS address. Real gateways also serve more than one host, and each host usually has its own certificate. This part adds the redirect, adds a second host with its own certificate, and shows what a wrong secret looks like.

## Redirect with `httpsRedirect`

A port 80 server can carry a `tls` block with only one field: `httpsRedirect: true`. With that field, the gateway answers every plain HTTP request with a `301` (moved permanently) response. The `Location` header of that response holds the same host and path with the scheme `https`. The gateway does not route the request, so no `VirtualService` rule is involved.

```yaml
- port:
    number: 80
    name: http
    protocol: HTTP
  hosts:
  - starfleet.example.com
  tls:
    httpsRedirect: true
```

## One server per host, one certificate per server

To serve a second host on port 443, add a second server with the same port number and a different `name`. Each server has its own `hosts` and its own `credentialName`. The gateway picks the certificate by SNI: the host name the client sends in the TLS handshake, before any HTTP request exists. That is why the gateway cannot choose a certificate from the `Host` header. The header arrives later, inside the encrypted connection.

The commands below need the `Gateway` `starfleet-gateway` (with one HTTPS server for `starfleet.example.com`), the `VirtualService` `bridge`, and the secret `starfleet-tls` in `istio-system`. They also need `GATEWAY_URL=localhost:8080` set in your shell.

<!-- astrona:playground:renew -->

### Create the second certificate in the wrong namespace

The second host is `probe.example.com`. Create its certificate:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout probe.key -out probe.crt \
  -subj "/CN=probe.example.com/O=starfleet"
```

Now create the secret next to the `Gateway`, in the `starfleet` namespace. This is a mistake on purpose, so you see how it fails:

```sh
kubectl create secret tls probe-tls -n starfleet --key=probe.key --cert=probe.crt
```

### Add the redirect and the second server

Replace `gateway-starfleet-gateway.yaml` with this file. It has three servers: port 80 with the redirect for both hosts, and one HTTPS server for each host:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
    - probe.example.com
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: https-starfleet
      protocol: HTTPS
    hosts:
    - starfleet.example.com
    tls:
      mode: SIMPLE
      credentialName: starfleet-tls
  - port:
      number: 443
      name: https-probe
      protocol: HTTPS
    hosts:
    - probe.example.com
    tls:
      mode: SIMPLE
      credentialName: probe-tls
```

Apply it:

```sh
kubectl apply -f gateway-starfleet-gateway.yaml
```

The new host needs a route. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe.example.com
  gateways:
  - starfleet-gateway
  http:
  - route:
    - destination:
        host: probe
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

### Test the redirect

Send a plain HTTP request and print the status code and the redirect address. Curl does not follow the redirect unless you add `-L`:

```sh
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

The status code is `301`, and the redirect address starts with `https://starfleet.example.com/productpage`. The address has no port number, so it means port `443`. Your playground serves HTTPS on local port `8443`, so following the redirect with `-L` would not reach it. In a real cluster, port `443` is the HTTPS port, and the redirect works as it is.

### Find the secret that the gateway cannot load

Send one HTTPS request for each host:

```sh
curl -sk -o /dev/null -w 'starfleet: %{http_code}\n' --resolve starfleet.example.com:8443:127.0.0.1 https://starfleet.example.com:8443/productpage
curl -sk -o /dev/null -w 'probe: %{http_code}\n' --resolve probe.example.com:8443:127.0.0.1 https://probe.example.com:8443/get
```

The `starfleet.example.com` request gets `200`. The `probe.example.com` request fails with `000`, because the handshake does not finish. HTTP and the `Gateway` look correct, and `kubectl` shows no error. Two commands show the cause:

```sh
istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system
kubectl logs -n istio-system deploy/istiod | grep probe-tls
```

The secret `kubernetes://probe-tls` has the status `WARMING`: the gateway asked for it and has no certificate. The `istiod` log line names the place where it looked, `istio-system/probe-tls`. The same symptom appears when the secret is in the right namespace but its name differs from `credentialName`: Istio looks for exactly that name, in `istio-system`.

### Move the secret and compare the certificates

Create the secret in the gateway's namespace, and remove the unused copy:

```sh
kubectl create secret tls probe-tls -n istio-system --key=probe.key --cert=probe.crt
kubectl delete secret probe-tls -n starfleet
```

Then ask for the certificate of each host. The only difference between the two commands is the name after `-servername`:

```sh
openssl s_client -connect 127.0.0.1:8443 -servername starfleet.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject
openssl s_client -connect 127.0.0.1:8443 -servername probe.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject
```

The first subject names `starfleet.example.com` and the second names `probe.example.com`. It is the same port and the same gateway pod, and the SNI picked a different certificate. The `probe.example.com` request from before now gets `200` as well.

You now know that `httpsRedirect: true` turns port 80 into a redirect to HTTPS, that each HTTPS server has its own `credentialName`, and that SNI chooses the certificate. A missing or misplaced secret leaves the secret in `WARMING`, and only that host fails. The open question is how to make the gateway demand a certificate from the client, and how to pass encrypted traffic on without opening it.

## Common pitfalls

> [!WARNING]
> - **Two HTTPS servers with the same `name` on port 443.** Each server on a port needs its own name. Use names like `https-starfleet` and `https-probe`.
> - **A `credentialName` that differs from the secret name.** Istio looks for exactly that name in `istio-system`. The secret stays in `WARMING`, and the handshake fails.
> - **Following the redirect on the playground.** The redirect address has no port, so it points at port `443`. Test the redirect with `curl` and no `-L`, and read the status code and the redirect address.
> - **Expecting a `VirtualService` to decide the redirect.** `httpsRedirect` is answered by the gateway before any route is read.
> - **Forgetting to add a new host to the port 80 server.** A host that is not listed there gets no redirect.

## Your mission: Secure An Ingress Gateway With HTTPS And A Redirect Lab

You can now give an ingress gateway a certificate from a secret, serve HTTPS for a host and redirect HTTP to it. The mission asks you to do this from a provided certificate and key, and to prove it with real requests.

Pause the playground, then start the lab and submit it:

```sh
astrona stop ats-014-playground-060-04
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-04/labs/lab-01
astrona submit -c sections/section-060/module-04/labs/lab-01
```

When you are done, remove the lab and start the playground again:

```sh
astrona destroy ats-014-lab-060-04-01
astrona start ats-014-playground-060-04
```
