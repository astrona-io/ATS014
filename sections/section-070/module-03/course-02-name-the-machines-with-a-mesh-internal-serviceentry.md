# Name The Machines With A MESH_INTERNAL ServiceEntry

A `WorkloadEntry` describes one machine outside Kubernetes, but no caller can reach it by a host name yet. The sidecar proxy of the caller only builds a cluster for a host that has a name and a port. A `ServiceEntry` adds both. A `ServiceEntry` adds a host to Istio's service registry, the list of hosts and endpoints that `istiod`, the control plane, sends to every sidecar proxy. It is often used for somebody else's service on the internet. This part uses it for a machine that you run yourself, and shows what that changes.

The commands below need the `freighter-vm-1` `WorkloadEntry` applied in your playground, with the label `app: freighter` and the address of the `freighter-vm-1` pod.

## A `ServiceEntry` for your own machines

Three settings change when the `ServiceEntry` is for your own machines instead of somebody else's service:

| Setting | Somebody else's service | Your own machines |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL`: the service is outside the mesh | `MESH_INTERNAL`: the service is part of the mesh |
| `resolution` | `DNS`: look up the host name to get addresses | `STATIC`: use the addresses written in the entries |
| Where the addresses come from | The DNS (Domain Name System) answer | A `workloadSelector` that matches `WorkloadEntry` labels |

The `workloadSelector` links the two objects. It selects `WorkloadEntry` objects in the same namespace by their labels, the same way a Kubernetes Service selects pods. It also selects pods with those labels, so one host can cover virtual machines and pods while you move a workload into Kubernetes. `resolution: STATIC` fits because the entries already hold the addresses, so there is nothing to look up.

<!-- astrona:playground:renew -->

The host name `freighter.starfleet.mesh` exists only in this object. The playground has Istio's DNS proxying switched on: the sidecar proxy answers DNS lookups for hosts in the service registry, so `curl` can resolve the name. Save this as `serviceentry-freighter.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: freighter
```

Apply it:

```sh
kubectl apply -f serviceentry-freighter.yaml
```

Then send a request to the new name and read the last line of the `shuttle` access log, where its sidecar proxy writes one line per request:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line trimmed):

```text
503
"GET /hostname HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end} ... "10.244.0.9:8080" outbound|8080||freighter.starfleet.mesh ...
```

The name works: the proxy used the cluster `outbound|8080||freighter.starfleet.mesh` and found the freighter's address. But the request fails with `503`. The response flags in the log explain why. `UF` means the connection to the upstream (the destination) failed, and `URX` means the proxy gave up after its retries. `WRONG_VERSION_NUMBER` is the TLS error: the `shuttle` proxy started a TLS handshake, and the freighter answered in plain HTTP.

## What `MESH_INTERNAL` changes

`MESH_INTERNAL` tells every proxy that the endpoints are part of the mesh. A workload in the mesh has a sidecar proxy, so the caller's proxy uses mTLS (mutual TLS, where both sides present a certificate) for every connection to it. A real virtual machine that runs `istio-agent`, the Istio program that starts its sidecar, accepts mTLS. The stand-in pod has no sidecar, so the TLS handshake fails.

| | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| --- | --- | --- |
| Host name, routing, `VirtualService` | yes | yes |
| `DestinationRule` policy (load balancing, outlier detection) | yes | yes |
| Caller's proxy uses mTLS on its own | no | yes |
| Identity from `serviceAccount` counts | no | yes |
| `AuthorizationPolicy` can name the machine | no | yes |

The last three rows are why `location` matters. `MESH_EXTERNAL` gives a host name and routing, so it looks like it works. It never gives the machine an identity.

The cluster configuration of the caller's proxy shows this choice. Each endpoint in a cluster can carry a `tlsMode-istio` match, which tells the proxy to use Istio mTLS for that endpoint. Count it in the freighter cluster:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn freighter.starfleet.mesh -o json | grep -c tlsMode-istio
```

```text
1
```

`1` means the cluster uses mTLS for the freighter. Now try the wrong fix that many people reach for first: mark the machine as outside the mesh. Save this as `serviceentry-freighter-external.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_EXTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: freighter
```

Apply it:

```sh
kubectl apply -f serviceentry-freighter-external.yaml
```

Then send the request and count again:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn freighter.starfleet.mesh -o json | grep -c tlsMode-istio
```

```text
200
0
```

The request succeeds, and the `tlsMode-istio` match is gone. It looks fixed, but you have told the mesh that your own machine is not part of it. It gets no identity and no mTLS, even after the real machine runs its own sidecar. Apply the `MESH_INTERNAL` version again:

```sh
kubectl apply -f serviceentry-freighter.yaml
```

## Turn off mTLS for the stand-in only

The stand-in pod can never accept mTLS, so the playground needs one extra object that a real machine with `istio-agent` would not need. A `DestinationRule` sets what happens after routing picks a host, including the TLS settings the caller's proxy uses toward it. With `tls` mode `DISABLE`, callers send plain HTTP to `freighter.starfleet.mesh`. The `ServiceEntry` stays `MESH_INTERNAL`.

Save this as `destinationrule-freighter.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: freighter
  namespace: starfleet
spec:
  host: freighter.starfleet.mesh
  trafficPolicy:
    tls:
      mode: DISABLE
```

Apply it:

```sh
kubectl apply -f destinationrule-freighter.yaml
```

Then check the result:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn freighter.starfleet.mesh
```

You should see:

```text
{
  "hostname": "freighter-vm-1-684c9b8695-65dlz"
}
SERVICE FQDN                 PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
freighter.starfleet.mesh     8080     -          outbound      EDS      freighter.starfleet
```

The freighter answers by name. The cluster `TYPE` is `EDS` (Endpoint Discovery Service): `istiod` sends the proxy the list of endpoints, taken from the `WorkloadEntry` objects, the same way it does for the pods behind a Kubernetes Service. The `DESTINATION RULE` column shows that the `DestinationRule` is attached.

Last, ask the `shuttle` proxy which endpoints stand behind the cluster:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.9:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
```

There is one endpoint: the address from your `WorkloadEntry`. From now on, load balancing, outlier detection and every other `DestinationRule` setting treat this machine like a pod.

> [!TIP]
> When a `MESH_INTERNAL` host fails with `503` and `WRONG_VERSION_NUMBER` in the access log, the caller's proxy is using mTLS toward a workload that does not. On a real virtual machine, check that `istio-agent` runs there before you change the `ServiceEntry`.

You can now give machines outside Kubernetes a host name with a `MESH_INTERNAL` `ServiceEntry`, and you know why `MESH_EXTERNAL` is the wrong fix for a failed TLS handshake. So far one machine stands behind the host. The next question is how a second machine joins the same host, and what happens when the selector and the labels do not agree.

## Common pitfalls

> [!WARNING]
> - **Using `MESH_EXTERNAL` for your own machine.** Requests get through, so it looks right, but the machine never gets an identity or mTLS.
> - **Expecting `MESH_INTERNAL` to work with a machine that has no sidecar.** The caller's proxy uses mTLS, and the request fails with `503 UF` and `WRONG_VERSION_NUMBER`.
> - **Keeping the `tls` `DISABLE` `DestinationRule` after the real machine runs `istio-agent`.** It is only for a machine that cannot accept mTLS.
> - **Using `resolution: DNS`.** The entries already hold the addresses. `STATIC` says so.
> - **A `workloadSelector` in another namespace than the entries.** It only selects `WorkloadEntry` objects in its own namespace.
