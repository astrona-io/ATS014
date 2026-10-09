# The Gateway Pod And Its Listener

Astronaut, this part answers two questions. What is the gateway, as a running program? And what does a `Gateway` object do to it? Neither is hard, but mixing the two up causes most of the confusion around ingress.

## A communications officer with no ship

Before you open the gate, look at who stands at it. The gateway is a program you already know, placed somewhere new.

### Same Envoy, different place

Every ship in the fleet has a communications officer on board: the sidecar proxy. The ingress gateway is the same Envoy program, standing alone at the spaceport arrival gate, with no ship of its own. The differences are all about where it runs:

| | Sidecar | Ingress gateway |
| --- | --- | --- |
| Runs | inside an app pod | in its own pod, on its own planet (`istio-ingress` here) |
| Containers in the pod | app + `istio-proxy` (`2/2`) | just the proxy (`1/1`) |
| Reached by | traffic caught inside the pod | a Kubernetes Service, usually `LoadBalancer` or `NodePort` (`ClusterIP` plus a port forward in the playground) |
| Set up by | `VirtualService` and `DestinationRule` for mesh traffic | a `Gateway` plus a `VirtualService` linked to it |
| Traffic direction | east-west | north-south |

Because it is the same Envoy, every tool you know works on it: `istioctl proxy-config listener`, `routes` and `endpoints`, and the flight log. You debug a gateway with the same commands as a sidecar.

<!-- astrona:playground:renew -->

### Look at the gate before you open it

First, the gateway pod and its `istio` label:

```sh
kubectl get pods -n istio-ingress -L istio
```

```text
NAME                             READY   STATUS    RESTARTS   AGE   ISTIO
istio-ingress-5f768fb4b6-j62c8   1/1     Running   0          92s   ingress
```

The pod is `1/1`: one container, no app. The `ISTIO` column shows its label, `istio=ingress`. Remember it; the `Gateway` needs it.

Then the Service in front of it:

```sh
kubectl get svc -n istio-ingress
```

```text
NAME            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                    AGE
istio-ingress   ClusterIP   10.96.80.93   <none>        15021/TCP,80/TCP,443/TCP   82s
```

The Service is `ClusterIP`, so the playground reaches it through the port forward on `127.0.0.1:8080`.

Now send a signal through the gate:

```sh
gateway_status /productpage
```

```text
000
```

`000` means curl got no reply at all. The gateway is healthy, but nothing has told it to listen on port `80` yet. That is the expected starting state.

## The `Gateway` object

The `Gateway` opens the gate and tunes it to a radio channel (a port). This piece shows the whole object (you apply it in a moment):

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
```

Read a `Gateway` as **"open a listener on some gateway pods"**. It does not route anything: there is no `destination` anywhere in it.

**`selector`** is a pod label selector. It is how the object finds the gateway pods to set up, and which label to use depends on how Istio was installed:

| Install method | Gateway pod label |
| --- | --- |
| Helm `gateway` chart installed as `istio-ingress` (this playground) | `istio: ingress` |
| `istioctl install` (`default` or `demo` profile) | `istio: ingressgateway` |

Many examples use `istio: ingressgateway`. Copy one onto a Helm install and no pod gets your listener. So look before you write: `kubectl get pods -n istio-ingress -L istio`.

**`servers[].port`** is the port **on the gateway Service**, with a `name` and a `protocol`. The protocol decides what the gate can read:

| `protocol` | The gateway will |
| --- | --- |
| `HTTP` | read each request: host and path routing, header matching |
| `HTTPS` | decrypt TLS with a `tls` block, then behave as `HTTP` |
| `TLS` | read only the server name the client asks for (SNI), then pass the stream on or decrypt it |
| `TCP` | move bytes, with no idea what is inside |

**`servers[].hosts`** is the set of `Host` headers this listener accepts. A signal whose `Host` is not in the list is not served. `*` accepts any host, and `*.example.com` any subdomain.

### Try a selector that matches nothing

See the most common gateway mistake on purpose: a selector from an `istioctl` install, on this Helm install. Save this as `gateway-starfleet-wrong-selector.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
```

Apply it:

```sh
kubectl apply -f gateway-starfleet-wrong-selector.yaml
```

```text
gateway.networking.istio.io/starfleet-gateway created
```

Then send a signal, and ask `istioctl analyze` and the gateway's own listeners:

```sh
gateway_status /productpage
istioctl analyze -n starfleet
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress
```

```text
000
Error [IST0101] (Gateway starfleet/starfleet-gateway) Referenced selector not found: "istio=ingressgateway"
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

(The `analyze` output is trimmed to its finding.)

Still `000`. Kubernetes accepted the object, but no pod carries `istio=ingressgateway`, so no gateway got the listener: there is no port `80` in the listener list, only the gateway's own health and metrics ports. `istioctl analyze` names the problem: `IST0101 Referenced selector not found`.

## The object and the pod live on different planets

Look at where things sit. The `Gateway` object lives next to your ships, but the pod it sets up does not.

```mermaid
flowchart LR
    G["Gateway in starfleet"] -->|"selector istio=ingress"| P["gateway pod in istio-ingress"]
    V["VirtualService in starfleet"] -->|"gateways field"| G
    P -->|"route"| S["bridge in starfleet"]
```

The `Gateway` and the `VirtualService` live on your app's planet, `starfleet`. The gateway pod they set up lives on another planet, `istio-ingress`, and the selector is the only thing joining them. That is normal: the object is configuration, and one shared gateway can serve `Gateway` objects from many planets.

### Open the listener, and get 404 instead of 000

Now use the right label. Save this as `gateway-starfleet.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
```

Apply it:

```sh
kubectl apply -f gateway-starfleet.yaml
```

```text
gateway.networking.istio.io/starfleet-gateway configured
```

Then send a signal, read the gate's flight log, and list its listeners again:

```sh
gateway_status /productpage
kubectl logs -n istio-ingress deploy/istio-ingress --tail=1
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress
```

```text
404
[2026-10-08T21:52:47.349Z] "GET /productpage HTTP/1.1" 404 NR route_not_found - "-" 0 0 2 - "10.244.0.6" "curl/8.7.1" "41e2a899-24c1-41a4-9977-007d40e3e149" "starfleet.example.com" "-" - - 127.0.0.1:80 127.0.0.1:54094 - -
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   80    ALL   Route: http.80
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

The answer changed from `000` to `404`. The connection now works, because a listener on port `80` exists, and it sends every signal to a route table called `http.80`. But that table has no flight plan yet, so the gateway answers `404` itself. The flight log marks it with **`NR`**, "no route". A `Gateway` alone gives you exactly this: somewhere for signals to arrive, and nowhere for them to go.

> [!TIP]
> Read the gate's answer before anything else: `000` means no listener (check the `selector`), `404 NR` means a listener with no matching route. That one difference tells you which object to look at.

## Common pitfalls

> [!WARNING]
> - **Expecting a `Gateway` to route anything.** It opens a listener. It has no `destination`, and on its own it gives `404 NR`.
> - **Copying `istio: ingressgateway` onto a Helm install.** No pod has that label, so no pod gets the listener and curl gets `000`. `istioctl analyze` reports `IST0101`.
> - **Declaring the wrong `protocol`.** `TCP` for HTTP traffic gives a working byte pipe with no host or path routing.
> - **Forgetting that `hosts` filters the `Host` header.** A signal whose `Host` is not in the list is not served by that listener.
> - **Looking for the gateway pod in your own namespace.** The object is yours; the pod is the shared one on the gateway's planet (`istio-ingress` here).

> *A `Gateway` opens a listener on the pods its `selector` matches. It holds no destination and routes nothing by itself.*

## Your mission: Open The Closed Gate

You can now find the gateway pod, read its labels, and open a listener with the right `selector`. Now prove it in a graded mission: a gate that answers nothing is waiting for you, and you have to open it without changing the flight plan behind it.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-01-02
astrona start ats-014-playground-060-01
```
