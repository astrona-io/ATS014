# Solution Walkthrough

Six objects, three outcomes. Two of them are the same `ServiceEntry` kind with opposite values for `location` — which is the distinction the whole section turns on.

---

## Step 1: Confirm Everything Is Refused

```sh
PARTNER=$(cat /tmp/partner-ip); VM=$(cat /tmp/vm-ip); BLOCKED=$(cat /tmp/blocked-ip)
echo "partner=$PARTNER  vm=$VM  blocked=$BLOCKED"
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy

for u in "http://$PARTNER:8443/" "http://$VM:8080/get" "http://$BLOCKED:8080/get"; do
  printf '%-32s -> ' "$u"
  kubectl -n integrations exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$u"
done
```

```text
partner=10.244.0.20  vm=10.244.0.22  blocked=10.244.0.21
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
http://10.244.0.20:8443/         -> 502
http://10.244.0.22:8080/get      -> 502
http://10.244.0.21:8080/get      -> 502
```

Everything refused. Note `legacy-vm` is refused too, even though it is in an injected namespace — it has no Service, so it is not in the registry either.

---

## Step 2: A — Register the Partner, With Both Ports

```sh
PARTNER=$(cat /tmp/partner-ip)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: integrations
spec:
  hosts:
    - partner.example.com
  addresses:
    - $PARTNER
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
    - address: $PARTNER
  exportTo:
    - "."
EOF
```

`MESH_EXTERNAL` because this is somebody else's API — you do not issue it an identity. `exportTo: ["."]` because a `ServiceEntry` is exported mesh-wide by default, and on a deny-by-default mesh one team's grant should not silently become everyone's.

---

## Step 3: A — Redirect And Originate

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner
  namespace: integrations
spec:
  hosts:
    - partner.example.com
  http:
    - match:
        - port: 8080
      route:
        - destination:
            host: partner.example.com
            port:
              number: 8443
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: partner
  namespace: integrations
spec:
  host: partner.example.com
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE
          sni: partner.example.com
          insecureSkipVerify: true
EOF
sleep 3
PARTNER=$(cat /tmp/partner-ip)
kubectl -n integrations exec deploy/tester -- curl -s --max-time 15 "http://$PARTNER:8080/"
```

```text
scheme=https
```

A plain `http://` call, and the endpoint — which speaks only TLS — reports it was reached over `https`. That is origination, proven by the destination rather than inferred from a status code.

`portLevelSettings` for 8443 only. At the top of `trafficPolicy` the same `tls` block would apply to port 8080 as well, and the whole arrangement would 503.

---

## Step 4: B — Bring Your Machine In

```sh
VM=$(cat /tmp/vm-ip)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm
  namespace: integrations
spec:
  address: $VM
  labels:
    app: legacy
  serviceAccount: legacy-sa
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: legacy
  namespace: integrations
spec:
  hosts:
    - legacy.integrations.svc
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  workloadSelector:
    labels:
      app: legacy
EOF
sleep 3
kubectl -n integrations exec deploy/tester -- \
  curl -s -o /dev/null -w 'by name: %{http_code}\n' --max-time 10 http://legacy.integrations.svc:8080/get
```

```text
by name: 200
```

Here is the section's central contrast, on one screen: two `ServiceEntry` objects, identical in shape, differing in `location`.

| | `partner` | `legacy` |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| Whose service | theirs | yours |
| Identity | none | `spiffe://cluster.local/ns/integrations/sa/legacy-sa` |
| `AuthorizationPolicy` can name it | no | yes |

`MESH_EXTERNAL` on the legacy entry would route perfectly well and fail the requirement — which is exactly why the grader checks the field rather than only the traffic.

---

## Step 5: C — Confirm the Third Is Still Refused

```sh
BLOCKED=$(cat /tmp/blocked-ip)
kubectl -n integrations exec deploy/tester -- \
  curl -s -o /dev/null -w 'blocked: %{http_code}\n' --max-time 10 "http://$BLOCKED:8080/get"
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
```

```text
blocked: 502
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
```

Two grants made, one refusal preserved, and the mesh still deny-by-default. That combination — precise allowances against a closed default — is the whole point of the section.

---

## Step 6: Review the Registry

```sh
istioctl proxy-config cluster deploy/tester -n integrations | grep -E 'partner|legacy'
```

```text
legacy.integrations.svc   8080   -   outbound   STATIC
partner.example.com       8080   -   outbound   STATIC
partner.example.com       8443   -   outbound   STATIC
```

Three clusters from two hosts — the partner has one per declared port, which is what made the 8080-to-8443 redirect possible.

---

## Common Mistakes

- **`MESH_EXTERNAL` on the legacy entry.** Traffic works, identity does not. The most likely way to fail while appearing to succeed.
- **`MESH_INTERNAL` on the partner entry.** Istio would expect mTLS to somebody else's API.
- **`tls` at the top of the partner `trafficPolicy`.** Applies to port 8080 too; the whole chain 503s.
- **Declaring only port 8443 on the partner.** The plaintext request has nowhere to arrive.
- **Omitting `exportTo` on the partner entry.** The grant becomes mesh-wide.
- **Omitting `serviceAccount` on the `WorkloadEntry`.** No identity.
- **Registering `blocked-api`, or relaxing the mesh to `ALLOW_ANY`.** Either fails the third requirement.
- **Creating a Service in `outside-mesh`, or injecting `legacy-vm`.** Both are back doors the grader checks for.
