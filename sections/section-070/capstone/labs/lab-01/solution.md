# Solution Walkthrough

The task needs six objects for three results. Two of them are `ServiceEntry` objects of the same shape with opposite values for `location`: `MESH_EXTERNAL` for the API of somebody else, and `MESH_INTERNAL` for your own machine. That difference is the main point of the task. A `ServiceEntry` adds a host to the service registry, which is the list of hosts that `istiod`, the Istio control plane, knows about. Items 1 to 4 deliver result A, the partner API. Items 5 and 6 deliver result B, your machine. Item 7 is result C. Items 8 to 14 prove the result.

---

## Start: Confirm That Everything Is Blocked

The task says that three endpoints exist, and that none of them is in the registry. Read the three addresses, check the outbound traffic policy of the mesh, and send one request to each endpoint from `tester`. Save the identity of the pods. Item 14 compares against it:

```sh
PARTNER=$(cat /tmp/partner-ip)
VM=$(cat /tmp/vm-ip)
BLOCKED=$(cat /tmp/blocked-ip)
echo "partner=$PARTNER  vm=$VM  blocked=$BLOCKED"
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
for url in "http://$PARTNER:8443/" "http://$VM:8080/get" "http://$BLOCKED:8080/get"; do
  printf '%-32s -> ' "$url"
  kubectl -n integrations exec deploy/tester -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$url"
done
kubectl -n integrations get serviceentry,workloadentry,virtualservice,destinationrule
kubectl -n outside-mesh get svc
kubectl -n integrations get pods | awk '{print $1,$2,$3}'
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n integrations get pod legacy-vm -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
partner=10.244.0.8  vm=10.244.0.10  blocked=10.244.0.9
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
rootNamespace: istio-system
http://10.244.0.8:8443/          -> 000
command terminated with exit code 56
http://10.244.0.10:8080/get      -> 000
command terminated with exit code 56
http://10.244.0.9:8080/get       -> 000
command terminated with exit code 56
NAME                                                   HOST                      AGE
destinationrule.networking.istio.io/legacy-plaintext   legacy.integrations.svc   1s
No resources found in outside-mesh namespace.
NAME READY STATUS
legacy-vm 1/1 Running
tester-69699fd775-fwbds 2/2 Running
NAME          UID
blocked-api   0743eb10-6c2f-4e97-8abc-df670a501cfc
partner-api   d74168a2-995f-4f0a-9fda-ad19fe4379e6
NAME        UID
legacy-vm   89ce478b-4af9-4798-aeb1-6590e603cdc2
```

All three requests are blocked. The sidecar proxy of `tester` sends a connection to an address outside the service registry to `BlackHoleCluster`, which closes it. The sidecar proxy is the Envoy container that Istio adds to a pod. No HTTP answer comes back, so `curl` prints `000` and exits with the code `56`, which means that the connection was reset. After a `ServiceEntry` adds an HTTP port, a blocked request on that port gets a `502` answer instead. The pod `legacy-vm` is blocked too, although it runs in the namespace `integrations`: it has no Service, so it is not in the registry either. The addresses in your run differ.

---

## Items 1 And 2: The Partner `ServiceEntry` With Both Ports

> **Task item 1:** A `ServiceEntry` named **`partner`** in `integrations` for the host **`partner.example.com`**, with the partner address in `spec.addresses`, `location` **`MESH_EXTERNAL`**, `resolution` **`STATIC`**, an `endpoints` entry for that address, and **`exportTo: ["."]`**.
>
> **Task item 2:** Two ports on it: **8080** with name `http` and protocol **`HTTP`**, and **8443** with name `https` and protocol **`HTTPS`**.

The location is `MESH_EXTERNAL`, because this is the API of somebody else: the mesh gives it no identity. `exportTo: ["."]` makes the host visible only in the namespace `integrations`. By default a `ServiceEntry` is visible in every namespace, and on a mesh that blocks everything else, the exception of one team should not become the exception of everyone. Port 8080 with the protocol `HTTP` is where the plain request of the application arrives. Port 8443 with the protocol `HTTPS` is where the encrypted request goes. Replace `<PARTNER>` in the YAML with the address that `echo $PARTNER` prints. Save this as `serviceentry-partner.yaml`:

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

```text
serviceentry.networking.istio.io/partner created
```

Check items 1 and 2. Print the spec:

```sh
kubectl -n integrations get serviceentry partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.8"],"endpoints":[{"address":"10.244.0.8"}],"exportTo":["."],"hosts":["partner.example.com"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"},{"name":"https","number":8443,"protocol":"HTTPS"}],"resolution":"STATIC"}
```

---

## Item 3: Route Port 8080 To Port 8443

> **Task item 3:** A `VirtualService` named **`partner`** that matches **port 8080** and routes to **port 8443** on the same host.

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

```text
virtualservice.networking.istio.io/partner created
```

Check item 3:

```sh
kubectl -n integrations get virtualservice partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"hosts":["partner.example.com"],"http":[{"match":[{"port":8080}],"route":[{"destination":{"host":"partner.example.com","port":{"number":8443}}}]}]}
```

---

## Item 4: Originate The TLS

> **Task item 4:** A `DestinationRule` named **`partner`** with `trafficPolicy.portLevelSettings` for **port 8443** only: `tls.mode` **`SIMPLE`**, `tls.sni` **`partner.example.com`**, and `insecureSkipVerify: true` (the certificate is self-signed).

TLS (Transport Layer Security) origination means that the sidecar proxy of the client opens the TLS connection itself, while the application sends plain HTTP. SNI (Server Name Indication) is the server name that the proxy sends at the start of the handshake. Put the `tls` block under `portLevelSettings` for port 8443. At the top level of `trafficPolicy`, the same block would apply to port 8080 too, and every request would fail. Save this as `destinationrule-partner.yaml`:

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

```text
destinationrule.networking.istio.io/partner created
```

Check item 4:

```sh
kubectl -n integrations get destinationrule partner -o jsonpath='{.spec}{"\n"}'
```

```text
{"host":"partner.example.com","trafficPolicy":{"portLevelSettings":[{"port":{"number":8443},"tls":{"insecureSkipVerify":true,"mode":"SIMPLE","sni":"partner.example.com"}}]}}
```

---

## Item 9: The Partner Answers Over TLS

> **Task item 9:** `GET http://<partner-ip>:8080/` from `tester` returns **200**, and the body contains **`scheme=https`**. A plain HTTP request reached an endpoint that only accepts TLS, so the sidecar proxy originated the TLS connection.

`istiod` sends the objects to the proxy. Wait a few seconds, then send a plain HTTP request:

```sh
kubectl -n integrations exec deploy/tester -- curl -s --max-time 15 "http://$PARTNER:8080/"
```

```text
scheme=https
```

The application sent a plain `http://` request, and the endpoint, which accepts only TLS, reports that it was reached over `https`. The destination itself proves that the sidecar proxy originated the TLS. A status code alone would not prove it.

---

## Item 5: The `WorkloadEntry` For Your Machine

> **Task item 5:** A `WorkloadEntry` named **`legacy-vm`** in `integrations` with the address of the machine, the label **`app: legacy`**, and `serviceAccount` **`legacy-sa`**.

A `WorkloadEntry` describes one machine outside Kubernetes. The `serviceAccount` gives it the identity `spiffe://cluster.local/ns/integrations/sa/legacy-sa`, which is the same identity that a pod running as that ServiceAccount has. Replace `<VM>` with the address that `echo $VM` prints. Save this as `workloadentry-legacy-vm.yaml`:

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

```text
workloadentry.networking.istio.io/legacy-vm created
```

Check item 5:

```sh
kubectl -n integrations get workloadentry \
  -o custom-columns=NAME:.metadata.name,ADDRESS:.spec.address,LABELS:.spec.labels,SA:.spec.serviceAccount
```

```text
NAME        ADDRESS       LABELS            SA
legacy-vm   10.244.0.10   map[app:legacy]   legacy-sa
```

---

## Item 6: The `ServiceEntry` For Your Machine

> **Task item 6:** A `ServiceEntry` named **`legacy`** in `integrations` for the host **`legacy.integrations.svc`**, with `location` **`MESH_INTERNAL`**, `resolution` **`STATIC`**, port **8080** with name `http` and protocol `HTTP`, and a `workloadSelector` that matches `app: legacy`.

A `WorkloadEntry` has no host name. A `ServiceEntry` with a `workloadSelector` selects the entry by its label, and gives it one. Save this as `serviceentry-legacy.yaml`:

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

```text
serviceentry.networking.istio.io/legacy created
```

Check item 6:

```sh
kubectl -n integrations get serviceentry legacy -o jsonpath='{.spec}{"\n"}'
```

```text
{"hosts":["legacy.integrations.svc"],"location":"MESH_INTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"}],"resolution":"STATIC","workloadSelector":{"labels":{"app":"legacy"}}}
```

The two `ServiceEntry` objects have the same shape and differ in `location`:

| | `partner` | `legacy` |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| Whose service | somebody else's | yours |
| Identity | none | `spiffe://cluster.local/ns/integrations/sa/legacy-sa` |
| An `AuthorizationPolicy` can name it | no | yes |

---

## Items 11 And 12: Your Machine Is Reachable By Name, As A Member Of The Mesh

> **Task item 11:** `GET http://legacy.integrations.svc:8080/get` returns **200**: the machine is reachable by host name.
>
> **Task item 12:** The legacy `ServiceEntry` is `MESH_INTERNAL`, and the `WorkloadEntry` carries `serviceAccount: legacy-sa`.

```sh
sleep 3
kubectl -n integrations exec deploy/tester -- \
  curl -s -o /dev/null -w 'by name: %{http_code}\n' --max-time 10 http://legacy.integrations.svc:8080/get
kubectl -n integrations get serviceentry legacy -o jsonpath='{.spec.location}{"\n"}'
kubectl -n integrations get workloadentry legacy-vm -o jsonpath='{.spec.serviceAccount}{"\n"}'
```

```text
by name: 200
MESH_INTERNAL
legacy-sa
```

The machine answers by host name. With `MESH_INTERNAL`, the proxy of `tester` would use mTLS (mutual TLS) toward the machine. The `DestinationRule` `legacy-plaintext`, which belongs to the environment, turns that off for this host, because the stand-in pod has no sidecar proxy. A real virtual machine would not need it. `MESH_EXTERNAL` on this entry would route requests just as well, and it would still fail the task, because the machine would have no identity.

---

## Items 7, 8 And 13: The Third Endpoint Stays Blocked

> **Task item 7:** Do not add `blocked-api` to the service registry, and do not change the mesh to `ALLOW_ANY`.
>
> **Task item 8:** The mesh is still `REGISTRY_ONLY`.
>
> **Task item 13:** `GET http://<blocked-ip>:8080/get` does **not** return 200.

```sh
kubectl -n integrations exec deploy/tester -- \
  curl -s -o /dev/null -w 'blocked: %{http_code}\n' --max-time 10 "http://$BLOCKED:8080/get"
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
kubectl -n integrations get serviceentry -o custom-columns=NAME:.metadata.name,HOSTS:.spec.hosts
```

```text
blocked: 502
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
rootNamespace: istio-system
NAME      HOSTS
legacy    [legacy.integrations.svc]
partner   [partner.example.com]
```

The third endpoint is still blocked. It now gets a `502` answer from the proxy, because port 8080 is an HTTP port in the registry. The mesh still blocks unknown destinations by default, and the registry holds two hosts only.

---

## Item 10: The TLS Block Is Under The Port

> **Task item 10:** The `tls` block of the partner `DestinationRule` is under `portLevelSettings` for port 8443, not at the top level of `trafficPolicy`.

```sh
kubectl -n integrations get destinationrule partner \
  -o jsonpath='top-level tls=[{.spec.trafficPolicy.tls}] port-level={.spec.trafficPolicy.portLevelSettings[0].port.number}{"\n"}'
```

```text
top-level tls=[] port-level=8443
```

There is no top-level `tls`, and the `tls` block belongs to port 8443. List the clusters of both hosts in the proxy of `tester` as a last review. A cluster is a named destination in Envoy:

```sh
istioctl proxy-config cluster deploy/tester -n integrations | grep -E 'partner|legacy'
```

```text
legacy.integrations.svc                                        8080      -          outbound      EDS              legacy-plaintext.integrations
partner.example.com                                            8080      -          outbound      EDS              partner.integrations
partner.example.com                                            8443      -          outbound      EDS              partner.integrations
```

The columns are the host, the port, the subset, the direction, the type and the `DestinationRule`. Two hosts give three clusters. The partner has one cluster for each declared port, and that is what lets the `VirtualService` route from port 8080 to port 8443.

---

## Item 14: No Service, And No Sidecar Proxy In `legacy-vm`

> **Task item 14:** No Service exists in `outside-mesh`, and `legacy-vm` still has no sidecar proxy.

```sh
kubectl -n outside-mesh get svc
kubectl -n integrations get pods | awk '{print $1,$2,$3}'
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n integrations get pod legacy-vm -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
No resources found in outside-mesh namespace.
NAME READY STATUS
legacy-vm 1/1 Running
tester-69699fd775-fwbds 2/2 Running
NAME          UID
blocked-api   0743eb10-6c2f-4e97-8abc-df670a501cfc
partner-api   d74168a2-995f-4f0a-9fda-ad19fe4379e6
NAME        UID
legacy-vm   89ce478b-4af9-4798-aeb1-6590e603cdc2
```

There is no Service in `outside-mesh`. The pod `legacy-vm` shows `1/1`, so it has no sidecar proxy, and all pods have the same `UID` values as at the start.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/capstone/labs/lab-01
```

The grader calls the three endpoints from `tester` and reads the objects.

---

## Mistakes That Fail The Grader

- **`MESH_EXTERNAL` on the legacy entry (items 6 and 12).** Requests work, but the machine has no identity. This is the most likely way to fail while it looks like it works.
- **`MESH_INTERNAL` on the partner entry (item 1).** The proxy of `tester` would then use Istio mTLS toward the API of somebody else.
- **`tls` at the top level of the partner `trafficPolicy` (items 4 and 10).** It applies to port 8080 too, and every request fails.
- **Declaring only port 8443 on the partner (item 2).** The plain HTTP request on port 8080 has no cluster to go to.
- **Leaving out `exportTo` on the partner entry (item 1).** The exception becomes visible in every namespace.
- **Leaving out `serviceAccount` on the `WorkloadEntry` (items 5 and 12).** The machine has no identity.
- **Adding `blocked-api` to the registry, or changing the mesh to `ALLOW_ANY` (items 7, 8 and 13).** Either one fails result C.
- **Creating a Service in `outside-mesh`, or injecting a sidecar proxy into `legacy-vm` (item 14).** The task checks for both.
