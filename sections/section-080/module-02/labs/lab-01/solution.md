# Solution Walkthrough

You build five objects in order, then prove the result with three separate checks: the response of the partner server, the egress gateway's access log, and the TLS settings in each proxy.

---

## Step 1: Check the starting state

Before you write anything, confirm the two facts the task depends on. Read the partner's IP address, send a plain request and a TLS request straight to it, and count the egress gateway's access log lines for the partner:

```sh
PARTNER=$(cat /tmp/partner-ip); echo "partner: $PARTNER"
kubectl -n egwtls-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'plain to 8443: %{http_code}\n' --max-time 10 "http://$PARTNER:8443/"
kubectl -n egwtls-demo exec deploy/tester -- curl -sk --max-time 10 "https://$PARTNER:8443/"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 | grep -c partner
```

```text
partner: 10.244.0.8
plain to 8443: 400
scheme=https
0
```

The partner server rejects plain text: nginx answers `400` to a plain request on its TLS port. It reports the scheme it was reached over. The egress gateway carries no traffic yet.

---

## Step 2: Add the host with both ports

The `ServiceEntry` adds `partner.example.com` to Istio's service registry. It needs the partner's IP address, so read it into a variable first:

```sh
PARTNER=$(cat /tmp/partner-ip)
```

Replace `<PARTNER>` in the YAML below with the real address. To see it, run `echo $PARTNER`.

Save this as `serviceentry-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: egwtls-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - <PARTNER>
  ports:
    - number: 8080
      name: http
      protocol: HTTP
    - number: 8443
      name: https
      protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PARTNER>
```

Apply it:

```sh
kubectl apply -f serviceentry-partner.yaml
```

Port 8080 is where the plain request from the sidecar proxy arrives. Port 8443 is where rule 2 sends it on. Both are needed.

---

## Step 3: Add the listener and its subset

The `Gateway` opens a listener on port 8080 of the egress gateway for the external host. Save this as `gateway-egress-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: egwtls-demo
spec:
  selector:
    istio: egressgateway
  servers:
    - port:
        number: 8080
        name: http
        protocol: HTTP
      hosts:
        - partner.example.com
```

Apply it:

```sh
kubectl apply -f gateway-egress-gateway.yaml
```

Rule 1 of the `VirtualService` names a subset of the egress gateway's Service, so that subset must exist. Save this as `destinationrule-egressgateway-for-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egressgateway-for-partner
  namespace: egwtls-demo
spec:
  host: istio-egressgateway.istio-system.svc.cluster.local
  subsets:
    - name: partner
```

Apply it:

```sh
kubectl apply -f destinationrule-egressgateway-for-partner.yaml
```

The listener is on **8080**, the port the egress gateway *receives* on. The egress gateway will *send* on 8443. These are two directions, so the two numbers do not have to match.

---

## Step 4: Add the two routing rules

Save this as `virtualservice-partner-through-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-through-egress
  namespace: egwtls-demo
spec:
  hosts:
    - partner.example.com
  gateways:
    - mesh
    - egress-gateway
  http:
    - match:
        - gateways: [mesh]
          port: 8080
      route:
        - destination:
            host: istio-egressgateway.istio-system.svc.cluster.local
            subset: partner
            port:
              number: 8080
    - match:
        - gateways: [egress-gateway]
          port: 8080
      route:
        - destination:
            host: partner.example.com
            port:
              number: 8443
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-through-egress.yaml
```

Rule 2's `port: 8443` is the important line. If it routes to 8080, the egress gateway sends plain text to a server that only speaks TLS. That failure looks like a TLS problem, but it is a routing problem.

Test now, before you add the last object:

```sh
PARTNER=$(cat /tmp/partner-ip)
kubectl -n egwtls-demo exec deploy/tester -- \
  curl -s -o /dev/null -w 'without origination: %{http_code}\n' --max-time 20 "http://partner.example.com:8080/"
```

```text
without origination: 400
```

The request reaches port 8443 as plain text, so the partner server answers `400`. This is the failure you get when the TLS `DestinationRule` is missing.

---

## Step 5: Originate TLS on the external host

Save this as `destinationrule-originate-tls-for-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: originate-tls-for-partner
  namespace: egwtls-demo
spec:
  # Scope the rule to the egress gateway's namespace. A DestinationRule for an
  # external host is visible mesh-wide by default, so every sidecar would also
  # originate TLS for it - the opposite of the point here, which is that the
  # sidecar speaks plain HTTP to the gateway and the gateway does the TLS.
  exportTo:
    - istio-system
  host: partner.example.com
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE
          sni: partner.example.com
          insecureSkipVerify: true
```

Apply it:

```sh
kubectl apply -f destinationrule-originate-tls-for-partner.yaml
```

Then check the result:

```sh
sleep 4
PARTNER=$(cat /tmp/partner-ip)
kubectl -n egwtls-demo exec deploy/tester -- curl -s --max-time 20 "http://partner.example.com:8080/"
```

```text
scheme=https
```

The rule names **`host: partner.example.com`**, the external host, not the egress gateway Service. A `DestinationRule` is applied by whichever proxy *calls* the host it names, and here that is the egress gateway. If you name `istio-egressgateway...` instead, nothing starts TLS toward the partner: that rule would apply to the sidecar proxy's hop to the egress gateway, which is plain HTTP on purpose.

If the sidecar proxies started TLS themselves, this object would look exactly the same. Only the proxy that applies it would change, because only the caller changes.

---

## Step 6: Prove the result three ways

First, prove that the egress gateway was in the path and sent the request on to port 8443. Read its newest log line for the partner:

```sh
kubectl -n istio-system logs deploy/istio-egressgateway --tail=5 | grep partner.example.com | tail -1
```

```text
[2026-10-08T23:49:16.014Z] "GET / HTTP/1.1" 200 - via_upstream - "-" 0 13 3 2 "10.244.0.9" "curl/8.22.0" "e17944c4-90fb-9b55-adb0-e55bcf4824bf" "partner.example.com:8080" "10.244.0.8:8443" outbound|8443||partner.example.com 10.244.0.6:53522 10.244.0.6:8080 10.244.0.9:54788 - -
```

The line shows a readable HTTP request, the upstream on **8443**, and the cluster `outbound|8443||partner.example.com`.

Second, prove that the TLS settings are on the egress gateway and not on the sidecar proxy. Count the `transportSocket` entries, the TLS settings of a cluster, in each proxy:

```sh
echo -n "gateway: "
istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system \
  --fqdn partner.example.com -o json | grep -c transportSocket
echo -n "sidecar: "
istioctl proxy-config cluster deploy/tester -n egwtls-demo \
  --fqdn partner.example.com -o json | grep -c transportSocket
```

```text
gateway: 1
sidecar: 0
```

One and zero is the shortest proof that the egress gateway, the proxy that calls the host, applies the rule. If the sidecar proxy started TLS itself, these two commands would give the opposite result.

Third, the server saw HTTPS: it answered `scheme=https` in step 5.

---

## Common mistakes

- **The TLS `DestinationRule` on the egress gateway Service.** Nothing starts TLS toward the partner, because that rule covers the sidecar proxy's hop, which is plain text on purpose.
- **Rule 2 routes to port 8080.** The egress gateway sends plain text to a server that only speaks TLS.
- **Only port 8443 in the `ServiceEntry`.** The task asks for both ports: 8080 for the plain request from the sidecar proxy, 8443 for the TLS hop from the egress gateway.
- **`tls` at the top of `trafficPolicy`.** It would apply to port 8080 as well.
- **No `sni` or no `insecureSkipVerify`.** The certificate names `partner.example.com` and is self-signed, so both are needed here.
- **Mixing up the two `DestinationRule` objects.** One names the egress gateway Service and holds an empty subset. The other names the external host and holds the TLS settings.
- **`mesh` missing from the top-level `gateways`.** Rule 1 never reaches the sidecar proxies, so the request goes straight to the partner and fails.
- **Counting the egress gateway's log lines without a starting count.** The log keeps growing, so compare the count before and after your request.
