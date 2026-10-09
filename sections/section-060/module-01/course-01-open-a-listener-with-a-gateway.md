# Open A Listener With A Gateway

Requests from outside the cluster need one place where they enter the mesh. In Istio, that place is the ingress gateway, and you configure it with a `Gateway` object. This part answers two questions. What is the ingress gateway, as a running program? And what does a `Gateway` object change in it? Most confusion around ingress comes from mixing up these two things.

## The ingress gateway is an Envoy proxy without an application

Before you write any configuration, look at the program that will receive it. It is a program you already know, running in a new place.

### Same Envoy, different place

Inside the mesh, every pod has a sidecar proxy: an Envoy container that Istio adds to the pod, so all inbound and outbound traffic of the pod passes through it. The ingress gateway is the same Envoy program. It runs in its own pod, with no application next to it, at the edge of the mesh. It accepts traffic from outside the cluster, which is called north-south traffic. Traffic between pods inside the mesh is called east-west traffic.

The differences between the two are all about where the proxy runs and how traffic reaches it:

| | Sidecar proxy | Ingress gateway |
| --- | --- | --- |
| Runs | inside an application pod | in its own pod, in its own namespace (`istio-ingress` here) |
| Containers in the pod | application + `istio-proxy` (`2/2`) | only the proxy (`1/1`) |
| Reached by | traffic that `iptables` rules send to it inside the pod | a Kubernetes Service, usually `LoadBalancer` or `NodePort` (`ClusterIP` plus a port forward in the playground) |
| Configured by | `VirtualService` and `DestinationRule` for traffic inside the mesh | a `Gateway` plus a `VirtualService` bound to it |
| Traffic direction | east-west | north-south |

Because it is the same Envoy, every tool you use on a sidecar proxy also works on the gateway. `istioctl proxy-config listener`, `routes` and `endpoints` read its configuration, and its access log shows one line per request. `istiod`, Istio's control plane, sends it configuration over xDS (the protocol `istiod` uses to push configuration to proxies while they run), just as it does for every sidecar.

<!-- astrona:playground:renew -->

### Look at the gateway before you configure it

First, list the gateway pod and show its `istio` label:

```sh
kubectl get pods -n istio-ingress -L istio
```

```text
NAME                             READY   STATUS    RESTARTS   AGE   ISTIO
istio-ingress-5f768fb4b6-j62c8   1/1     Running   0          92s   ingress
```

The pod is `1/1`: one container, no application. The `ISTIO` column shows its label, `istio=ingress`. Remember this label, because the `Gateway` object needs it.

Next, list the Service in front of the pod:

```sh
kubectl get svc -n istio-ingress
```

```text
NAME            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                    AGE
istio-ingress   ClusterIP   10.96.80.93   <none>        15021/TCP,80/TCP,443/TCP   82s
```

The Service type is `ClusterIP`, so nothing outside the cluster can reach it directly. The playground reaches it through a port forward from `127.0.0.1:8080` to the Service's port `80`.

Now send a request through the gateway. The `gateway_status` helper below sends one request for a path, with a `Host` header (`starfleet.example.com` unless you name another host), and prints only the HTTP status code. Paste it into your terminal if you have not done so yet, then call it:

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
gateway_status /productpage
```

```text
000
```

`000` means curl got no response at all. The gateway pod is healthy, but no configuration tells its Envoy to listen on port `80` yet. This is the expected starting state.

## The `Gateway` object

A `Gateway` is the Istio object that opens a listener on the gateway pods. A listener is the part of Envoy that accepts connections on one port. The quickest way to learn the fields is to see the most common mistake first.

### A selector that matches no pod

Many examples use the label `istio: ingressgateway`, which belongs to an `istioctl` install. This playground installs the gateway with Helm. Save this as `gateway-starfleet-wrong-selector.yaml`:

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

Then send a request, run `istioctl analyze`, and list the gateway's listeners:

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

(The `analyze` output is shortened to its finding.)

The answer is still `000`. Kubernetes stored the object, but no pod carries the label `istio=ingressgateway`, so `istiod` sent the listener to no gateway. The listener list has no port `80`, only the gateway's own health port (`15021`) and metrics port (`15090`). `istioctl analyze` names the problem: `IST0101 Referenced selector not found`.

### What each field does

This failed object already shows every field a `Gateway` needs. Read a `Gateway` as "open a listener on some gateway pods". It does not route anything: it has no `destination` field.

**`selector`** is a pod label selector. `istiod` uses it to find the gateway pods that get the listener. The right label depends on how Istio was installed:

| Install method | Gateway pod label |
| --- | --- |
| Helm `gateway` chart installed as `istio-ingress` (this playground) | `istio: ingress` |
| `istioctl install` (`default` or `demo` profile) | `istio: ingressgateway` |

So check the label before you write the selector: `kubectl get pods -n istio-ingress -L istio`.

**`servers[].port`** is the port on the gateway Service, with a `name` and a `protocol`. The protocol decides how much of each request Envoy can read:

| `protocol` | The gateway will |
| --- | --- |
| `HTTP` | read each request: routing by host and path, matching on headers |
| `HTTPS` | decrypt TLS (Transport Layer Security) with a `tls` block, then act as `HTTP` |
| `TLS` | read only the server name the client asks for (SNI, Server Name Indication), then forward the encrypted stream or decrypt it |
| `TCP` | forward bytes without reading them |

**`servers[].hosts`** is the list of `Host` header values this listener accepts. A request whose `Host` is not in the list is not served. `*` accepts any host, and `*.example.com` accepts any subdomain of `example.com`.

## The object and the pod live in different namespaces

The `Gateway` object and the pod it configures do not sit in the same namespace. This diagram shows how the objects connect:

```mermaid
flowchart LR
    G["Gateway in starfleet"] -->|"selector istio=ingress"| P["gateway pod in istio-ingress"]
    V["VirtualService in starfleet"] -->|"gateways field"| G
    P -->|"route"| S["bridge in starfleet"]
```

The diagram shows the `Gateway` selecting the gateway pod by label, a `VirtualService` pointing at the `Gateway`, and the gateway pod sending requests to `bridge`.

The `Gateway` and the `VirtualService` live in the application's namespace, `starfleet`. The gateway pod lives in `istio-ingress`, and the label selector is the only link between them. This is normal: the object is configuration, and one shared gateway can serve `Gateway` objects from many namespaces.

### Open the listener and get 404 instead of 000

Now use the label that the gateway pod really carries. Save this as `gateway-starfleet.yaml`:

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

Then send a request, read the gateway's access log, and list its listeners again:

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

The answer changed from `000` to `404`. The connection now works, because Envoy has a listener on port `80`. The listener sends every request to a route table called `http.80`. That table has no routes yet, so Envoy answers `404` itself. The access log marks it with the response flag **`NR`**, which means "no route".

> [!TIP]
> Read the gateway's answer before anything else: `000` means no listener (check the `selector`), and `404 NR` means a listener with no matching route. That one difference tells you which object to look at.

You now know that the ingress gateway is an Envoy proxy in its own pod, and that a `Gateway` opens a listener on the pods its `selector` matches. A `Gateway` alone gives requests a place to arrive, but nowhere to go. The open question is how to give the gateway a route to `bridge`.

## Common pitfalls

> [!WARNING]
> - **Expecting a `Gateway` to route anything.** It opens a listener. It has no `destination`, and on its own it gives `404 NR`.
> - **Copying `istio: ingressgateway` onto a Helm install.** No pod has that label, so no pod gets the listener and curl gets `000`. `istioctl analyze` reports `IST0101`.
> - **Declaring the wrong `protocol`.** `TCP` for HTTP traffic gives a working connection with no routing by host or path.
> - **Forgetting that `hosts` filters the `Host` header.** A request whose `Host` is not in the list is not served by that listener.
> - **Looking for the gateway pod in your own namespace.** The `Gateway` object is in your namespace; the pod is the shared one in the gateway's namespace (`istio-ingress` here).

## Your mission: Fix A Gateway Selector That Matches No Pod Lab

You can now find the gateway pod, read its labels, and open a listener with the right `selector`. In the lab, a gateway gives no response to any request, and you must fix the `Gateway` without changing the `VirtualService` behind it.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-01/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-01/labs/lab-02
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-060-01-02
astrona start ats-014-playground-060-01
```
