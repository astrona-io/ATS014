# Solution Walkthrough

Two objects. The mesh is already deny-by-default, so this is about granting one host precisely — and then proving the grant brought Istio's features with it.

---

## Step 1: Confirm the Starting State

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

Both refused. That `502` is the mesh saying "not in the registry" — DNS and the network are fine, and the pods are running. Confirm that last part so you know the 502 is a decision rather than a failure:

```sh
kubectl -n outside-mesh get pods -o wide
```

```text
NAME            READY   STATUS    IP
forbidden-api   1/1     Running   10.244.0.15
partner-api     1/1     Running   10.244.0.14
```

---

## Step 2: Register the Partner Endpoint

```sh
PARTNER=$(cat /tmp/partner-ip)
cat > serviceentry-partner-api.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner-api
  namespace: egress-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - $PARTNER
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: $PARTNER
  exportTo:
    - "."
EOF
kubectl apply -f serviceentry-partner-api.yaml
```

```text
serviceentry.networking.istio.io/partner-api created
```

Note the heredoc is **unquoted** (`<<EOF`) so the shell substitutes `$PARTNER`.

Each field is doing a specific job:

- **`addresses`** is what lets the sidecar recognise traffic aimed at that IP and match it to this entry. Without it, a request to the raw address has nothing to match and stays a 502.
- **`protocol: HTTP`** is the one that matters for step 4. With `TCP` you would get a working connection and no timeout, no retries, no routing.
- **`location: MESH_EXTERNAL`** because this is somebody else's service — no mesh identity, no mTLS.
- **`resolution: STATIC` plus `endpoints`** because the address is known and fixed. `DNS` would ask the proxy to resolve `partner.example.com`, which resolves nowhere.
- **`exportTo: ["."]`** because the default is mesh-wide. Without it, every namespace in the cluster gains access to this host.

---

## Step 3: Verify the Grant Is Precise

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

One host in the cluster list, one endpoint open, the other still refused. That asymmetry is the whole point of `REGISTRY_ONLY` plus [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/): egress is a list you maintain rather than an assumption you inherit.

---

## Step 4: Put a Timeout on It

A registered host is an ordinary host, so every [`VirtualService`](https://istio.io/latest/docs/reference/config/networking/virtual-service/) feature applies:

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-partner-api.yaml <<'EOF'
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
EOF
kubectl apply -f virtualservice-partner-api.yaml
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

Two seconds against a five-second endpoint, with the `UT` flag from section 040. The `VirtualService` names `partner.example.com` — the host from the `ServiceEntry`, not the IP — because that is the registry name the request now resolves to internally.

This is the step that fails if `protocol` was `TCP`: the proxy would have no idea where one request ends, so a `timeout` would bound nothing and you would wait the full five seconds.

---

## Common Mistakes

- **Omitting `spec.addresses`.** The host is registered but the sidecar cannot match traffic aimed at the raw IP. Still 502.
- **`protocol: TCP`.** A working connection with no layer-7 features — the timeout silently does nothing.
- **`resolution: DNS`.** `partner.example.com` resolves nowhere; `STATIC` with `endpoints` is what fits a known address.
- **Omitting `exportTo`.** The entry is exported mesh-wide by default.
- **Listing both addresses.** Registering the forbidden endpoint too fails check 10.
- **Relaxing the mesh to `ALLOW_ANY`.** It makes both endpoints work and fails check 8 — the task is a precise grant, not a blanket one.
- **Creating a Service in `outside-mesh`.** That would put the endpoint in the registry through the back door; the grader rejects it.
- **Pointing the `VirtualService` at the IP.** It must name the `ServiceEntry` host.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [VirtualService API](https://istio.io/latest/docs/reference/config/networking/virtual-service/) — the whole object: `hosts`, `gateways`, and every field an `http` rule can carry
- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `hosts`, `ports`, `location`, `resolution` and `endpoints`
- [Istio Kubernetes Gateway API task](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) — `GatewayClass`, `Gateway`, `HTTPRoute`, `parentRefs` and `allowedRoutes`
- [HTTPRoute API](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPRoute) — `timeout` alongside `retries`, `fault` and `mirror` on one rule
- [Configuration scoping](https://istio.io/latest/docs/ops/configuration/mesh/configuration-scoping/) — how `exportTo` and `Sidecar` together decide what a proxy sees
- [MeshConfig outboundTrafficPolicy](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy) — `ALLOW_ANY` versus `REGISTRY_ONLY`
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
