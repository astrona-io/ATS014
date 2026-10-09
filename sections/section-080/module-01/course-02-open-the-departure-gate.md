# Open The Departure Gate

Astronaut, the gate needs two objects before any flight plan can use it. A `Gateway` tells the gate's pods which signals to accept, and a `DestinationRule` gives the shuttle a named way to reach the gate. Both look odd the first time you read them. This part explains why they are written the way they are.

## The `Gateway` object

A `Gateway` configures the gateway's pods. Its `selector` finds them by label, and each entry in `servers` opens a port on them for some host names. For the departure gate in your playground:

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

Three fields matter:

- **`selector: istio: egress`** picks the pods of the Helm-installed gate.
- **`protocol: TLS` with `tls.mode: PASSTHROUGH`** means the gate does **not** decrypt anything. It passes the sealed stream on as it is. How it still knows where to send it is the subject of the next part.
- **`hosts: httpbin.org`** is the field that reads backwards.

## The host list reads backwards

`servers[].hosts` lists **`httpbin.org`**: the **outside** host name, not anything inside your cluster.

Read the object from the gate's point of view: *"which host names will I serve signals for?"* The gate is going to receive signals bound for `httpbin.org`, so that is the host it must accept. The signals arrive at the gate's own Service address, but they still name `httpbin.org`: in the `Host` header for plain HTTP, or in the TLS handshake for HTTPS. That name is what the gate matches on.

Putting the gate's own name there, `istio-egress.istio-egress.svc.cluster.local`, is a common first attempt. It gives you a gate that refuses every signal you send it.

## The `DestinationRule` with an empty subset

Most egress examples, including Istio's own, add an object that looks pointless:

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

A subset with a name and **no labels**. It selects every pod of the gate's Service, so it narrows nothing. Note the full host name: the gate's Service lives on another planet, the namespace `istio-egress`, so a short name would not find it.

It is a name tag on the docking instructions, not a filter. With several outside hosts sent through one gate, each gets its own subset, so the proxy configuration and the flight logs keep them apart instead of mixing them into one bucket. And it is not optional: once a flight plan names the subset, deleting the `DestinationRule` breaks the route.

<!-- astrona:playground:renew -->

### Apply the `Gateway` and the `DestinationRule`

The `ServiceEntry` for `httpbin.org` must still be applied. Save the `Gateway` above as `gateway-egress.yaml`, then apply it:

```sh
kubectl apply -f gateway-egress.yaml
```

Save the `DestinationRule` above as `destinationrule-egress-gateway.yaml`, then apply it:

```sh
kubectl apply -f destinationrule-egress-gateway.yaml
```

Then check the result. Look at the shuttle's clusters for the gate:

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

The empty subset turned into a cluster of its own for every port of the gate's Service. The one the next part uses is `443` with the subset `httpbin-org`.

### See that nothing changed yet

Look at the gate's listeners again, and send a signal:

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

Two facts here:

- **The gate still has no listener on `443`.** For a `PASSTHROUGH` server, Istio only builds the listener once a `VirtualService` gives it a route for the host. A `Gateway` alone opens nothing you can see.
- **The shuttle still flies direct**, to an internet address. The `Gateway` configures the gate's pods, and the `DestinationRule` only describes how to reach the gate. Neither tells the shuttle to go there.

Both objects are in place and do nothing yet. That is on purpose: you apply them **before** the flight plan that uses them. Then the moment the flight plan arrives, everything it points at already exists. This order is called "make before break".

## Common pitfalls

> [!WARNING]
> - **An internal host name in `servers[].hosts`.** It must be the outside host the gate serves, here `httpbin.org`. Read the object from the gate's point of view.
> - **The wrong `selector`.** `istio: egress` on the Helm chart, `istio: egressgateway` on the `demo` profile. A `Gateway` that selects no pod does nothing.
> - **A short host name in the `DestinationRule`.** The gate's Service is in the namespace `istio-egress`. Write its full name.
> - **Deleting the "pointless" `DestinationRule`.** Once a flight plan names its subset, the shuttle has nowhere to send the signal without it.
> - **Expecting a listener from the `Gateway` alone.** A `PASSTHROUGH` server gets its listener only when a `VirtualService` routes the host through the gate.

> *The `Gateway` names the outside host it will serve, and the empty subset gives the shuttle a named way to the gate. Neither moves a single signal.*
