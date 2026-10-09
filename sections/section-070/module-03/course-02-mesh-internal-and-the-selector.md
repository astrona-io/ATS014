# `MESH_INTERNAL` And The Selector

Astronaut, a `WorkloadEntry` describes one old ship, but nobody can call it by name yet. A `ServiceEntry` gives it that name and a port, like a beacon the freighter answers to. You know `ServiceEntry` as the way to add a planet from another solar system to the star chart. Here it does something different: it adds a ship that is **yours**.

The commands below need the `freighter-vm-1` `WorkloadEntry` applied in your playground, with the label `app: freighter` and the address of the `freighter-vm-1` pod.

## The `ServiceEntry` for your own machines

Three fields change when the `ServiceEntry` is for your own machines instead of somebody else's service:

| Field | Somebody else's service | Your own machines |
| --- | --- | --- |
| `location` | `MESH_EXTERNAL`: a stranger's ship | **`MESH_INTERNAL`**: one of ours |
| `resolution` | `DNS`: look the name up | **`STATIC`**: use the addresses written in the entries |
| where the addresses come from | the name system (DNS) | a **`workloadSelector`** that matches `WorkloadEntry` labels |

The **`workloadSelector`** is the link between the two objects. It picks `WorkloadEntry` objects **in the same namespace** by their labels, the same way a Kubernetes Service picks pods. It can also pick pods with those labels, which is how one service can cover virtual machines and pods while you move a workload into Kubernetes.

**`resolution: STATIC`** fits because the entries already hold the addresses. Nothing needs to be looked up.

<!-- astrona:playground:renew -->

### Give the freighter a name

The host name `freighter.starfleet.mesh` exists nowhere except in this object. Save this as `serviceentry-freighter.yaml`:

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

Then send a signal to the new name and read the shuttle's flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (log line trimmed):

```text
503
"GET /hostname HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end} ... "10.244.0.9:8080" outbound|8080||freighter.starfleet.mesh ...
```

The name works: the proxy found the cluster `outbound|8080||freighter.starfleet.mesh` and the freighter's address. But the signal fails with `503`. The flags `UF` (upstream connection failure) and `URX` (gave up after retries) say the connection broke. `WRONG_VERSION_NUMBER` says why: the shuttle's proxy started the secret handshake (mutual TLS), and the freighter answered in plain HTTP.

## What `MESH_INTERNAL` changes

`MESH_INTERNAL` tells every proxy "this is one of ours". One of ours has a communications officer on board, so the shuttle's proxy opens every signal with the secret handshake. A real virtual machine with `istio-agent` answers it. Your stand-in has no officer, so the handshake fails.

| | `MESH_EXTERNAL` | `MESH_INTERNAL` |
| --- | --- | --- |
| Host name, routing, `VirtualService` | yes | yes |
| `DestinationRule` policy (load balancing, outlier detection) | yes | yes |
| Proxy starts the secret handshake by itself | no | yes |
| Identity from `serviceAccount` counts | no | yes |
| `AuthorizationPolicy` can name the machine | no | yes |

The last three rows are the point of this module. `MESH_EXTERNAL` gives you a name and routing, so it **looks** like it works. It never gives the machine an identity.

### See the handshake in the proxy's orders

The proxy decides to start the handshake from a setting on the cluster called `tlsMode-istio`. Count it:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn freighter.starfleet.mesh -o json | grep -c tlsMode-istio
```

```text
1
```

`1` means the cluster has the "start the handshake" setting. Now try the tempting wrong fix: call the freighter a stranger. Save this as `serviceentry-freighter-external.yaml`:

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

Then send the signal and count again:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn freighter.starfleet.mesh -o json | grep -c tlsMode-istio
```

```text
200
0
```

The signal arrives, and the handshake setting is gone. It looks fixed, but you have told the mesh that your own freighter is a stranger: no identity, and no handshake ever, even after the real machine gets its own officer. Put `MESH_INTERNAL` back:

```sh
kubectl apply -f serviceentry-freighter.yaml
```

## Switch the handshake off for the stand-in only

Your stand-in can never answer the handshake, so you need one extra object that a real onboarded machine would not need. A `DestinationRule` holds the docking instructions for one host. With `tls` mode `DISABLE`, it tells callers to approach `freighter.starfleet.mesh` in plain HTTP. The `ServiceEntry` stays `MESH_INTERNAL`.

### Approach without the handshake

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

The freighter answers by name. The cluster's `TYPE` is `EDS`: mission control sends the proxy the list of addresses, taken from the `WorkloadEntry` objects, exactly as it does for the pods behind a Service. The `DESTINATION RULE` column shows your docking instructions are attached.

### Look the freighter up on the star chart

Ask the shuttle's proxy which addresses stand behind the new cluster:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.9:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
```

One endpoint: the address from your `WorkloadEntry`. From now on, load balancing, outlier detection and every other `DestinationRule` setting treat this machine like any pod.

> [!TIP]
> When a `MESH_INTERNAL` host fails with `503` and `WRONG_VERSION_NUMBER` in the flight log, the caller's proxy is speaking mutual TLS to a machine that is not. On a real virtual machine, check that `istio-agent` is running there before you touch the `ServiceEntry`.

## Common pitfalls

> [!WARNING]
> - **Using `MESH_EXTERNAL` for your own machine.** It routes, so it looks right, but the machine never gets an identity or the handshake.
> - **Expecting `MESH_INTERNAL` to work with a machine that has no sidecar.** The caller starts the handshake, and the signal fails with `503 UF` and `WRONG_VERSION_NUMBER`.
> - **Keeping the `tls` `DISABLE` `DestinationRule` after the real machine is onboarded.** It is only for a machine that cannot answer the handshake.
> - **Using `resolution: DNS`.** The entries already hold the addresses. `STATIC` says so.
> - **A `workloadSelector` in another namespace than the entries.** It only picks `WorkloadEntry` objects in its own namespace.
