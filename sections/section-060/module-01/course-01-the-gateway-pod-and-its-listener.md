# Part 1 — The Gateway Pod And Its Listener

> Prerequisite: [the module landing page](./course.md). Next: [Part 2 — Binding Routes With `gateways:`](./course-02-binding-routes-with-gateways.md).

Two things to establish: what the gateway actually is as a running process, and what a `Gateway` object does to it. Neither is complicated, and the split between them causes most of the confusion in this section.

## A sidecar with no application beside it

The ingress gateway is the same Envoy binary that runs in every injected pod. The differences are all about deployment:

| | Sidecar | Ingress gateway |
| --- | --- | --- |
| Runs | inside an application pod | in its own pod, usually in `istio-system` |
| Containers in the pod | app + `istio-proxy` (`2/2`) | just the proxy (`1/1`) |
| Reached by | traffic interception inside the pod | a Kubernetes Service, usually `LoadBalancer` or `NodePort` |
| Configured by | `VirtualService` / `DestinationRule` for mesh traffic | `Gateway` + `VirtualService` bound to it |
| Traffic direction | east-west | north-south |

Because it is the same Envoy, every diagnostic tool you already know works on it unchanged — `istioctl proxy-config listeners/routes/clusters`, the access log, `pilot-agent request GET stats`. That is worth remembering: a gateway problem is debugged with the same commands as a sidecar problem.

> [!TIP]
> **Try it — a gateway with no configuration**
>
> ```sh
> kubectl -n istio-system get pods -l istio=ingressgateway
> kubectl -n istio-system get svc istio-ingressgateway
> kubectl -n ingress-demo get gateway,virtualservice
> curl -s -o /dev/null -w '%{http_code}\n' http://$GATEWAY_URL/book
> ```
>
> Expect something like:
>
> ```text
> NAME                                    READY   STATUS    AGE
> istio-ingressgateway-6d9c5b8f7c-4kx2n   1/1     Running   7m
> NAME                   TYPE           EXTERNAL-IP   PORT(S)
> istio-ingressgateway   LoadBalancer   <pending>     15021:31234/TCP,80:32000/TCP,443:31400/TCP
> No resources found in ingress-demo namespace.
> 404
> ```
>
> Three things: the pod is `1/1` — one container, no application — the Service's `EXTERNAL-IP` is `<pending>` because `kind` has no load balancer, and the request returns `404` because no `Gateway` has opened a listener it recognises. All three are the expected starting state.

## The `Gateway` object

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: booking-gateway
  namespace: ingress-demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - booking.ica.local
```

Read `Gateway` as **"configure a listener on some gateway pods"**. It does not route anything — there is no `destination` anywhere in it.

**`selector`** is a **pod label selector**, and it is how this object finds the workload to configure. `istio: ingressgateway` is the label carried by the gateway pod the standard profiles install. Two consequences worth holding:

- Running a second gateway with different labels — a separate internal gateway, say — means pointing a different `Gateway` at it via those labels. The object is not tied to any particular deployment by name.
- A `selector` matching nothing is not an error. The object exists, configures no proxy, and nothing works. `istioctl analyze` catches this one.

**`servers[].port`** is the port **on the gateway pod**, with a `name` and an explicit `protocol`. The protocol matters more than it looks:

| `protocol` | The gateway will |
| --- | --- |
| `HTTP` | parse requests — host and path routing, header matching, all of layer 7 |
| `HTTPS` | terminate TLS (with a `tls` block), then behave as HTTP |
| `TLS` | inspect SNI and either passthrough or terminate, without parsing HTTP |
| `TCP` | move bytes, with no layer-7 awareness at all |

Declaring `TCP` for HTTP traffic gives you a working byte pipe and no routing, which is a confusing result to debug backwards.

**`servers[].hosts`** is the set of `Host` headers this listener accepts. A request whose `Host` is not in the list is not served by it. `*` is allowed and matches anything; `*.example.com` matches a subdomain.

## The namespace split that catches everyone

```text
   ingress-demo                          istio-system
   ────────────                          ────────────
   Gateway  booking-gateway   ───────►   Pod  istio-ingressgateway
     (the configuration)     selector      (the process it configures)
   VirtualService booking
   Deployment/Service booking-service
```

The `Gateway` **object** lives in your application namespace. The gateway **pod** it configures lives in `istio-system`. That is normal, correct, and the usual arrangement — the object is configuration, and the selector connects it to a pod somewhere else entirely.

It also means a `Gateway` in your namespace can configure a shared, cluster-wide gateway. Part 2 covers the reverse case, where the `Gateway` object itself lives elsewhere.

## Applying it alone changes nothing

A listener with no routes attached serves nothing. This is worth seeing deliberately, because "I created the Gateway and it still 404s" is a common first result and it is not a fault.

> [!TIP]
> **Try it — open the listener, and still get 404**
>
> ```sh
> kubectl apply -f - <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: Gateway
> metadata:
>   name: booking-gateway
>   namespace: ingress-demo
> spec:
>   selector:
>     istio: ingressgateway
>   servers:
>     - port:
>         number: 80
>         name: http
>         protocol: HTTP
>       hosts:
>         - booking.ica.local
> EOF
> sleep 2
> curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
> istioctl proxy-config listener deploy/istio-ingressgateway -n istio-system | head -5
> ```
>
> Expect something like:
>
> ```text
> gateway.networking.istio.io/booking-gateway created
> 404
> ADDRESSES PORT  MATCH                         DESTINATION
> 0.0.0.0   8080  ALL                           Route: http.8080
> ```
>
> Still 404 — but the listener now exists. The gateway is listening on 8080 internally (mapped from port 80 on the Service) and pointing at a route table called `http.8080`, which is currently empty. That is the state a `Gateway` alone produces: somewhere for requests to arrive, and nothing to do with them.

> *`Gateway` opens a listener on pods its `selector` matches; it contains no destination and routes nothing by itself.*

## Reference

- [Ingress gateways task](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/) — the upstream walkthrough this module follows.
- [Gateway API (networking.istio.io)](https://istio.io/latest/docs/reference/config/networking/gateway/) — `selector`, `servers`, `port`, `hosts` and the `tls` block.
- [Deploying a gateway](https://istio.io/latest/docs/setup/additional-setup/gateway/) — running additional or custom gateways, and the labels they carry.
- `istioctl proxy-config listener deploy/istio-ingressgateway -n istio-system` — what the `Gateway` object actually produced.
