# Match Paths With pathType And Read The Generated Routes

A Kubernetes `Ingress` is an object that describes how HTTP (Hypertext Transfer Protocol) requests from outside the cluster reach a Service inside it. Its rules look a lot like the routes in an Istio `VirtualService`, but they follow Kubernetes rules, not Istio rules. One field in particular has the same name in both APIs (Application Programming Interfaces) and behaves differently. This part shows the shape of a rule, that difference, and the routes that `istiod`, Istio's control plane, builds from an `Ingress`.

## The shape of a rule

An `Ingress` rule names a host, then a list of paths, and for each path a Service and a port:

```text
 rules[].host                              the host name the request asks for
 rules[].http.paths[].path                 the path to compare
 rules[].http.paths[].pathType             how to compare it: Exact, Prefix or ImplementationSpecific
 rules[].http.paths[].backend.service      the Service (name and port) that gets the request
```

Two details matter. First, `host` is optional: a rule without a `host` matches any host name. Second, `backend.service` names a Kubernetes Service directly. A `VirtualService` can send requests to a subset (a named group of a Service's pods, selected by labels) and can split them by weight. An `Ingress` backend has neither, so you cannot send a share of the requests to one version of a Service.

## `pathType`, and the trap

Every path needs a `pathType`, and the value decides how the gateway compares the request path with the rule. There are three values:

| Value | Matches |
| --- | --- |
| `Exact` | exactly this path, and nothing below it |
| `Prefix` | this path, compared **element by element** between the `/` signs |
| `ImplementationSpecific` | whatever the controller decides. Avoid it when you want predictable results |

The trap is `Prefix`. It does not compare characters. It splits the path at every `/` and compares the elements. So a `Prefix` of `/anything/dock` matches `/anything/dock` and `/anything/dock/7`, but **not** `/anything/docking`: the last element is `docking`, not `dock`.

Istio's own `uri: { prefix: ... }` match in a `VirtualService` compares characters. So the same word means two different things in two APIs:

| Request path | `Ingress` `pathType: Prefix` of `/anything/dock` | Istio `uri: { prefix: /anything/dock }` |
| --- | --- | --- |
| `/anything/dock` | matches | matches |
| `/anything/dock/7` | matches | matches |
| `/anything/docking` | **no match** | **matches** |
| `/anything/dockyard` | **no match** | **matches** |

When you translate an `Ingress` into a `VirtualService` and want the same behaviour, a `pathType: Prefix` of `/anything/dock` becomes two matches: an `exact` match on `/anything/dock` and a `prefix` match on `/anything/dock/`.

### Send requests to the probe

The best way to see the difference is to send real requests. The commands below need the `istio` `IngressClass` (with `spec.controller: istio.io/ingress-controller`) in the cluster, and `GATEWAY_URL=localhost:8080` set in your shell. The playground forwards that local port to port `80` of the ingress gateway, the Envoy proxy at the edge of the mesh that serves every `Ingress`.

<!-- astrona:playground:renew -->

Add two paths for the `probe` Service to the `Ingress`: one with `Prefix` and one with `Exact`. The `probe` pods answer any path under `/anything`. So if a request to such a path gets `404`, the gateway refused it, not the `probe` pod. Save this as `ingress-starfleet.yaml`, replacing the old file:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: starfleet
  namespace: starfleet
spec:
  ingressClassName: istio
  rules:
  - host: starfleet.example.com
    http:
      paths:
      - path: /productpage
        pathType: Prefix
        backend:
          service:
            name: bridge
            port:
              number: 9080
      - path: /anything/dock
        pathType: Prefix
        backend:
          service:
            name: probe
            port:
              number: 8000
      - path: /status/200
        pathType: Exact
        backend:
          service:
            name: probe
            port:
              number: 8000
```

Apply it:

```sh
kubectl apply -f ingress-starfleet.yaml
```

Then send one request to each path and print the status code:

```sh
for p in /anything/dock /anything/dock/7 /anything/docking /anything/dockyard /status/200 /status/200/extra; do
  printf '%-20s -> ' "$p"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" "http://$GATEWAY_URL$p"
done
```

```text
/anything/dock       -> 200
/anything/dock/7     -> 200
/anything/docking    -> 404
/anything/dockyard   -> 404
/status/200          -> 200
/status/200/extra    -> 404
```

The path `/anything/docking` starts with the characters `/anything/dock`, and it still gets `404`, because `Prefix` compares whole elements. The path `/status/200/extra` gets `404` too, because `Exact` matches nothing below the path.

### Prove that the gateway refused the request

A `404` can come from the gateway or from the application. To find out which, send the same request to the `probe` Service directly from the `shuttle` pod, without the gateway:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe:8000/anything/docking
```

```text
200
```

The `probe` pod answers `200`, so the `404` came from the gateway. The gateway's access log confirms it:

```sh
kubectl logs -n istio-system deploy/istio-ingressgateway --tail=6 | grep -E "docking|extra"
```

You should see these lines (shortened):

```text
[2026-10-08T22:11:03.908Z] "GET /anything/docking HTTP/1.1" 404 NR route_not_found - "-" 0 0 7 - "10.244.0.6" "curl/8.7.1" "afda1c94-..." "starfleet.example.com" "-" - - 127.0.0.1:80 ...
[2026-10-08T22:11:03.932Z] "GET /status/200/extra HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.6" "curl/8.7.1" "bbee12da-..." "starfleet.example.com" "-" - - 127.0.0.1:80 ...
```

`NR` is a response flag, a short code in the Envoy access log that says why a request failed. `NR` means "no route": the gateway found no rule for that path, so it answered `404` itself, and the `probe` pod never saw the request.

## What `istiod` builds from an `Ingress`

Istio does not run a separate program for `Ingress` objects. `istiod` translates each `Ingress` into the same kind of route table that a `Gateway` with a `VirtualService` would produce. It then sends that configuration to the gateway over xDS, the protocol `istiod` uses to push configuration to proxies while they run. So the usual `istioctl proxy-config` commands work on it too.

Look at the gateway's route table for port `80`, and check that your namespace has no `Gateway` or `VirtualService`:

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system
kubectl get gateway,virtualservice -n starfleet
```

You should see this (shortened to the `starfleet.example.com` rows):

```text
NAME        VHOST NAME                   DOMAINS                   MATCH                         VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     PathPrefix:/anything/dock     starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     PathPrefix:/productpage       starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /status/200                   starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
No resources found in starfleet namespace.
```

Three things in this output are worth reading:

- **`PathPrefix:`** is the element-by-element `Prefix` match. The `Exact` path shows as the plain path `/status/200`.
- **The `VIRTUAL SERVICE` column** names an object that ends in `-autogenerated-k8s-ingress`. `istiod` builds it in memory; it does not exist in Kubernetes. That is why `kubectl get virtualservice` finds nothing.
- **The order is not the order you wrote.** The `Ingress` API has no "first rule wins" list. The most specific path wins, and the controller decides the details. If two paths overlap, you cannot see or control which one the gateway checks first.

You now know how `pathType` decides which paths match, how to prove that a `404` came from the gateway, and that `istiod` turns the `Ingress` into ordinary gateway routes. The rules so far only handle plain HTTP. The next question is how an `Ingress` adds HTTPS, and where its certificate must live.

## Common pitfalls

> [!WARNING]
> - **Reading `Prefix` as a character prefix.** It compares whole elements between `/` signs: `/anything/dock` does not match `/anything/docking`.
> - **Translating `pathType: Prefix` straight into `uri.prefix`.** The Istio match accepts more paths. Use an `exact` match plus a `prefix` match on the path with a trailing `/`.
> - **Using `ImplementationSpecific`.** Its meaning depends on the controller, so the same file can behave differently with another controller.
> - **Expecting the order of your paths to decide anything.** The `Ingress` API picks the most specific path, not the first one you wrote.
> - **Blaming the backend for a `404`.** Check the gateway's access log: `404 NR` means the gateway had no route for the path.
