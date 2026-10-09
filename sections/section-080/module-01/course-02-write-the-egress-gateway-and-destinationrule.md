# Write The Egress `Gateway` And Its `DestinationRule`

An egress gateway carries no traffic until routing sends traffic to it, and routing needs two objects in place first. A **`Gateway`** tells the egress gateway's pods which requests to accept. A **`DestinationRule`** gives the sidecar proxies a named way to reach the egress gateway. Both look odd the first time you read them, so this part explains why each one is written the way it is.

The commands below need the `ServiceEntry` `httpbin-org` in `starfleet` applied. It adds `httpbin.org` on port `443`, protocol `TLS`, to the service registry.

## The `Gateway` object

A `Gateway` configures the pods of a gateway. Its `selector` finds the pods by label, and each entry in `servers` opens a port on them for a list of host names. For the egress gateway in your playground, the `Gateway` accepts encrypted traffic for `httpbin.org` on port `443`.

<!-- astrona:playground:renew -->

Save this as `gateway-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: egress-gateway
  namespace: starfleet
spec:
  selector:
    istio: egress
  servers:
  - port:
      number: 443
      name: tls
      protocol: TLS
    hosts:
    - httpbin.org
    tls:
      mode: PASSTHROUGH
```

Apply it:

```sh
kubectl apply -f gateway-egress.yaml
```

Three fields matter here:

- **`selector: istio: egress`** picks the pods of the egress gateway that Helm installed.
- **`protocol: TLS` with `tls.mode: PASSTHROUGH`** means the egress gateway does **not** decrypt anything. TLS (Transport Layer Security) is the protocol that encrypts HTTPS. In `PASSTHROUGH` mode the gateway forwards the encrypted stream as it is, and routes it by a name it can read without decrypting.
- **`hosts: httpbin.org`** is the field that looks backwards.

## The host list names the outside host

`servers[].hosts` lists **`httpbin.org`**. That is the **outside** host name, not the name of anything inside your cluster.

Read the object from the egress gateway's point of view: *"for which host names do I accept requests?"* The egress gateway receives requests that are addressed to `httpbin.org`, so that is the host it must accept. The requests arrive at the gateway's own Service address, but they still carry the name `httpbin.org`. For plain HTTP the name is in the `Host` header. For HTTPS it is in the TLS handshake. That name is what the egress gateway matches on.

A common first attempt puts the gateway's own Service name there, `istio-egress.istio-egress.svc.cluster.local`. That gives you an egress gateway that refuses every request you send it.

## The `DestinationRule` with an empty subset

With the `Gateway` in place, the sidecars still need a way to name the egress gateway as a destination. Most egress examples, including Istio's own, add a `DestinationRule` that looks pointless. A **`DestinationRule`** sets what happens after routing picks a host, and it can define **subsets**: named groups of a Service's pods, selected by labels.

Save this as `destinationrule-egress-gateway.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egress-gateway-for-httpbin-org
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: httpbin-org
```

Apply it:

```sh
kubectl apply -f destinationrule-egress-gateway.yaml
```

The subset has a name and **no labels**. It selects every pod of the egress gateway's Service, so it narrows nothing. Note the full host name: the egress gateway's Service is in the namespace `istio-egress`, so a short name would not find it from `starfleet`.

The subset works as a label for one outside host, not as a filter. When several outside hosts go through one egress gateway, each gets its own subset. The proxy configuration and the access logs then keep the hosts apart instead of mixing them into one cluster. The subset is also not optional: once a `VirtualService` names it, deleting the `DestinationRule` breaks the route.

## Check what the two objects changed

Now check the result in the `shuttle` sidecar. Its **clusters** are Envoy's named destinations, each one a group of endpoints it can send requests to:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet | grep -E "SERVICE|istio-egress"
```

You should see:

```text
SERVICE FQDN                                    PORT      SUBSET          DIRECTION     TYPE             DESTINATION RULE
istio-egress.istio-egress.svc.cluster.local     80        -               outbound      EDS              egress-gateway-for-httpbin-org.starfleet
istio-egress.istio-egress.svc.cluster.local     443       -               outbound      EDS              egress-gateway-for-httpbin-org.starfleet
istio-egress.istio-egress.svc.cluster.local     15021     -               outbound      EDS              egress-gateway-for-httpbin-org.starfleet
istio-egress.istio-egress.svc.cluster.local     80        httpbin-org     outbound      EDS              egress-gateway-for-httpbin-org.starfleet
istio-egress.istio-egress.svc.cluster.local     443       httpbin-org     outbound      EDS              egress-gateway-for-httpbin-org.starfleet
istio-egress.istio-egress.svc.cluster.local     15021     httpbin-org     outbound      EDS              egress-gateway-for-httpbin-org.starfleet
```

The empty subset became a cluster of its own for every port of the egress gateway's Service. The route through the egress gateway uses port `443` with the subset `httpbin-org`.

Next, look at the egress gateway's listeners again, and send a request:

```sh
istioctl proxy-config listener deploy/istio-egress -n istio-egress
call_external
log_shuttle
```

You should see (log line trimmed):

```text
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
200 0.482396s
  exit=0
"- - -" 0 - - - "-" 901 4875 594 - "-" "-" "-" "-" "98.88.155.171:443" outbound|443||httpbin.org ... httpbin.org -
```

This output shows two facts. First, **the egress gateway still has no listener on `443`.** For a `PASSTHROUGH` server, `istiod` builds the listener only when a `VirtualService` gives it a route for the host. A `Gateway` alone opens nothing you can see.

Second, **`shuttle` still sends the request direct**, to an internet address. The `Gateway` configures the egress gateway's pods, and the `DestinationRule` only describes how to reach the egress gateway. Neither one tells the `shuttle` sidecar to go there.

Both objects are in place and do nothing yet. That is on purpose: you apply them **before** the `VirtualService` that uses them. Then, the moment the `VirtualService` arrives, everything it points at already exists. This order is called "make before break".

You now have an egress gateway that will accept `httpbin.org` and a named cluster that leads to it. The open question is how one `VirtualService` makes the `shuttle` sidecar use that cluster and makes the egress gateway forward the request.

## Common pitfalls

> [!WARNING]
> - **An internal host name in `servers[].hosts`.** It must be the outside host the egress gateway accepts, here `httpbin.org`. Read the object from the gateway's point of view.
> - **The wrong `selector`.** `istio: egress` on the Helm chart, `istio: egressgateway` on the `demo` profile. A `Gateway` that selects no pod does nothing.
> - **A short host name in the `DestinationRule`.** The egress gateway's Service is in the namespace `istio-egress`. Write its full name.
> - **Deleting the `DestinationRule` because it looks pointless.** Once a `VirtualService` names its subset, the `shuttle` sidecar has no cluster to send the request to without it.
> - **Expecting a listener from the `Gateway` alone.** A `PASSTHROUGH` server gets its listener only when a `VirtualService` routes the host through the egress gateway.
