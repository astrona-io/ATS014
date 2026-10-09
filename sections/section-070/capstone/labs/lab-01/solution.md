# Solution Walkthrough

The task needs six objects for three results. Two of them are `ServiceEntry` objects of the same shape with opposite values for `location`: `MESH_EXTERNAL` for somebody else's API and `MESH_INTERNAL` for your own machine. That difference is the main point of the task.

## Step 1: Confirm that everything is blocked

Read the three addresses, check the outbound traffic policy of the mesh, and send one request to each endpoint from `tester`:

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

All three requests are blocked. The `tester` sidecar proxy sends a request to an address outside the service registry to `BlackHoleCluster`, and returns `502`. The `legacy-vm` pod is blocked too, even though it runs in the `integrations` namespace: it has no Service, so it is not in the registry either.

## Step 2: A: Add the partner to the registry, with both ports

In the YAML below, replace `<PARTNER>` with the address that `echo $PARTNER` prints. Save this as `serviceentry-partner.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner
  namespace: integrations
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
  exportTo:
    - "."
```

Apply it:

```sh
kubectl apply -f serviceentry-partner.yaml
```

The location is `MESH_EXTERNAL` because this is somebody else's API: the mesh gives it no identity. `exportTo: ["."]` makes the host visible only in the `integrations` namespace. By default a `ServiceEntry` is visible in every namespace, and on a mesh that blocks everything else, one team's exception should not become everyone's.

## Step 3: A: Route port 8080 to port 8443 and originate TLS

The caller sends plain HTTP to port 8080. A `VirtualService` routes those requests to port 8443 of the same host. Save this as `virtualservice-partner.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f virtualservice-partner.yaml
```

A `DestinationRule` then tells the `tester` proxy to open a TLS connection to port 8443. This is TLS origination: the application sends plain HTTP, and the sidecar proxy does the TLS handshake. Save this as `destinationrule-partner.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f destinationrule-partner.yaml
```

Then check the result:

```sh
sleep 3
PARTNER=$(cat /tmp/partner-ip)
kubectl -n integrations exec deploy/tester -- curl -s --max-time 15 "http://$PARTNER:8080/"
```

```text
scheme=https
```

The application sent a plain `http://` request, and the endpoint, which only accepts TLS, reports that it was reached over `https`. The destination itself proves that the sidecar proxy originated TLS; a status code alone would not.

The `tls` block sits under `portLevelSettings` for port 8443 only. At the top level of `trafficPolicy`, the same block would apply to port 8080 as well, and every request would fail with `503`.

## Step 4: B: Add your machine as a member of the mesh

In the YAML below, replace `<VM>` with the address that `echo $VM` prints. Save this as `workloadentry-legacy-vm.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm
  namespace: integrations
spec:
  address: <VM>
  labels:
    app: legacy
  serviceAccount: legacy-sa
```

Apply it:

```sh
kubectl apply -f workloadentry-legacy-vm.yaml
```

A `WorkloadEntry` describes one machine outside Kubernetes, but it has no host name. A `ServiceEntry` with a `workloadSelector` selects the entry by its label and gives it one. Save this as `serviceentry-legacy.yaml`:

```yaml
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
```

Apply it:

```sh
kubectl apply -f serviceentry-legacy.yaml
```

Then check the result:

```sh
sleep 3
kubectl -n integrations exec deploy/tester -- \
  curl -s -o /dev/null -w 'by name: %{http_code}\n' --max-time 10 http://legacy.integrations.svc:8080/get
```

```text
by name: 200
```

With `MESH_INTERNAL`, the `tester` proxy would use mTLS (mutual TLS) toward the machine. The `legacy-plaintext` `DestinationRule` that the lab created turns that off for this host, because the stand-in pod has no sidecar proxy. A real virtual machine running `istio-agent` would not need it.

The two `ServiceEntry` objects have the same shape and differ in `location`:

| | `partner` | `legacy` |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| Whose service | somebody else's | yours |
| Identity | none | `spiffe://cluster.local/ns/integrations/sa/legacy-sa` |
| `AuthorizationPolicy` can name it | no | yes |

`MESH_EXTERNAL` on the legacy entry would route requests just as well and still fail the requirement. That is why the grader checks the field and not only the traffic.

## Step 5: C: Confirm that the third endpoint is still blocked

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

Two hosts are in the registry, the third endpoint is still blocked, and the mesh still blocks unknown destinations by default.

## Step 6: Review the clusters in the proxy

List the clusters for both hosts in the `tester` proxy. In Envoy, a cluster is a named destination with a list of endpoints:

```sh
istioctl proxy-config cluster deploy/tester -n integrations | grep -E 'partner|legacy'
```

```text
legacy.integrations.svc   8080   -   outbound   STATIC
partner.example.com       8080   -   outbound   STATIC
partner.example.com       8443   -   outbound   STATIC
```

Two hosts give three clusters. The partner has one cluster per declared port, which is what lets the `VirtualService` route from port 8080 to port 8443.

Send the setup for grading with `astrona submit -c sections/section-070/capstone/labs/lab-01`.

## Common mistakes

- **`MESH_EXTERNAL` on the legacy entry.** Requests work, but the machine has no identity. This is the most likely way to fail while it looks like it works.
- **`MESH_INTERNAL` on the partner entry.** The `tester` proxy would then use Istio mTLS toward somebody else's API.
- **`tls` at the top level of the partner `trafficPolicy`.** It applies to port 8080 too, and every request fails with `503`.
- **Declaring only port 8443 on the partner.** The plain HTTP request on port 8080 has no cluster to go to.
- **Leaving out `exportTo` on the partner entry.** The exception becomes visible in every namespace.
- **Leaving out `serviceAccount` on the `WorkloadEntry`.** The machine has no identity.
- **Adding `blocked-api` to the registry, or changing the mesh to `ALLOW_ANY`.** Either one fails the third requirement.
- **Creating a Service in `outside-mesh`, or injecting a sidecar proxy into `legacy-vm`.** The grader checks for both.
