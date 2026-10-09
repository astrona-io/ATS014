# Solution Walkthrough

You need two objects. The mesh already refuses unknown hosts, so the task is to add one endpoint to the service registry precisely, and then prove that the new entry brings Istio's features with it.

---

## Step 1: Confirm the starting state

First check the mesh-wide policy, read the two addresses, and send one request to each endpoint from `tester`:

```sh
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
PARTNER=$(cat /tmp/partner-ip);   echo "partner:   $PARTNER"
FORBIDDEN=$(cat /tmp/forbidden-ip); echo "forbidden: $FORBIDDEN"

for ip in $PARTNER $FORBIDDEN; do
  printf '%-16s -> ' "$ip"
  kubectl -n egress-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "http://$ip:8080/get"
done
```

```text
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
partner:   10.244.0.14
forbidden: 10.244.0.15
10.244.0.14      -> 502
10.244.0.15      -> 502
```

Both are refused. That `502` comes from the `tester` pod's sidecar proxy: the host is not in the service registry. DNS and the network are fine, and the pods are running. Check that last part, so you know the `502` is a decision of the proxy and not a failure:

```sh
kubectl -n outside-mesh get pods -o wide
```

```text
NAME            READY   STATUS    IP
forbidden-api   1/1     Running   10.244.0.15
partner-api     1/1     Running   10.244.0.14
```

---

## Step 2: Add the partner endpoint to the registry

Read the partner address into a variable:

```sh
PARTNER=$(cat /tmp/partner-ip)
```

Replace `<PARTNER>` in the YAML below with the real address. To see it, run `echo $PARTNER`.

Save this as `serviceentry-partner-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner-api
  namespace: egress-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - <PARTNER>
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PARTNER>
  exportTo:
    - "."
```

Apply it:

```sh
kubectl apply -f serviceentry-partner-api.yaml
```

```text
serviceentry.networking.istio.io/partner-api created
```

Each field does one job:

- **`addresses`** lets the sidecar proxy match traffic sent to that IP address to this entry. Without it, a request to the raw address matches nothing and still gets `502`.
- **`protocol: HTTP`** matters for step 4. With `TCP` you would get a working connection with no timeout, no retries and no routing.
- **`location: MESH_EXTERNAL`**, because this is somebody else's service: no mesh identity and no mTLS (mutual TLS).
- **`resolution: STATIC` plus `endpoints`**, because the address is known and fixed. `DNS` would make the proxy look up `partner.example.com`, which resolves nowhere.
- **`exportTo: ["."]`**, because the default is every namespace. Without it, every namespace in the cluster could reach this host.

---

## Step 3: Check that only one endpoint is open

Look for the host in the `tester` pod's sidecar proxy, then call both endpoints again:

```sh
istioctl proxy-config cluster deploy/tester -n egress-demo | grep partner
for ip in $(cat /tmp/partner-ip) $(cat /tmp/forbidden-ip); do
  printf '%-16s -> ' "$ip"
  kubectl -n egress-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "http://$ip:8080/get"
done
```

```text
partner.example.com   8080   -   outbound   STATIC
10.244.0.14      -> 200
10.244.0.15      -> 502
```

The proxy now has one cluster for the host, the partner endpoint answers, and the forbidden endpoint is still refused. That difference is the point of `REGISTRY_ONLY` plus `ServiceEntry`: outbound traffic is a list of hosts you keep, not something you inherit.

---

## Step 4: Put a timeout on the host

A host in the registry is an ordinary host, so every `VirtualService` feature applies to it. Save this as `virtualservice-partner-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-api
  namespace: egress-demo
spec:
  hosts:
    - partner.example.com
  http:
    - timeout: 2s
      route:
        - destination:
            host: partner.example.com
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-api.yaml
```

Then check the result. The `sleep` gives the proxy a moment to receive the new configuration:

```sh
sleep 3
PARTNER=$(cat /tmp/partner-ip)
kubectl -n egress-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} in %{time_total}s\n' --max-time 20 "http://$PARTNER:8080/delay/5"
kubectl -n egress-demo logs deploy/tester -c istio-proxy --tail=3 | grep UT | head -1
```

```text
504 in 2.049s
[2026-09-27T14:02:11.771Z] "GET /delay/5 HTTP/1.1" 504 UT upstream_response_timeout ...
```

The request to a five-second endpoint ended after two seconds, with the `UT` flag (upstream timeout) in the access log of the `tester` pod's sidecar proxy. The `VirtualService` names `partner.example.com`, the host from the `ServiceEntry`, and not the IP address. That is the registry name the proxy matches the request to.

This step fails if the port `protocol` is `TCP`. The proxy would then not know where one request ends, so a `timeout` would limit nothing and you would wait the full five seconds.

---

## Common Mistakes

- **Leaving out `spec.addresses`.** The host is in the registry, but the sidecar proxy cannot match traffic sent to the raw IP address. Still `502`.
- **`protocol: TCP`.** A working connection with no HTTP features: the timeout silently does nothing.
- **`resolution: DNS`.** `partner.example.com` resolves nowhere; `STATIC` with `endpoints` fits a known address.
- **Leaving out `exportTo`.** The entry is exported to every namespace by default.
- **Listing both addresses.** Adding the forbidden endpoint too fails check 10.
- **Changing the mesh to `ALLOW_ANY`.** Both endpoints then work, and check 8 fails. The task is one precise permission, not an open mesh.
- **Creating a Service in `outside-mesh`.** That would put the endpoint in the registry another way; the grader rejects it.
- **Pointing the `VirtualService` at the IP address.** It must name the `ServiceEntry` host.
