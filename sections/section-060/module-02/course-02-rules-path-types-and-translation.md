# Rules, Path Types And Translation

Astronaut, an `Ingress` rule looks a lot like a flight plan, but it follows Kubernetes' rules, not Istio's. One field in particular behaves differently from the Istio field with the same name. This part shows the rule's shape, that difference, and what mission control builds from it.

## The shape of a rule

An `Ingress` rule names a host, then a list of paths, and for each path a Service and a port:

```text
 rules[].host                              the host name the signal asks for
 rules[].http.paths[].path                 the path to compare
 rules[].http.paths[].pathType             how to compare it: Exact, Prefix or ImplementationSpecific
 rules[].http.paths[].backend.service      the Service (name and port) that gets the signal
```

Two details matter:

- **`host` is optional.** A rule without a `host` matches any host name.
- **`backend.service` names a Kubernetes Service directly.** There is no subset and no weight, so you cannot send a share of signals to one ship class.

## `pathType`, and the trap

Every path needs a `pathType`. There are three:

| Value | Matches |
| --- | --- |
| `Exact` | exactly this path, and nothing below it |
| `Prefix` | this path, compared **part by part** between the `/` signs |
| `ImplementationSpecific` | whatever the controller decides. Avoid it when you want predictable results |

The trap is `Prefix`. It does not compare letters. It splits the path at every `/` and compares the pieces. So a `Prefix` of `/anything/dock` matches `/anything/dock` and `/anything/dock/7`, but **not** `/anything/docking`: the last piece is `docking`, not `dock`.

Istio's own `uri: { prefix: ... }` in a `VirtualService` compares letters. The same word means two different things in two APIs:

| Signal's path | `Ingress` `pathType: Prefix` of `/anything/dock` | Istio `uri: { prefix: /anything/dock }` |
| --- | --- | --- |
| `/anything/dock` | matches | matches |
| `/anything/dock/7` | matches | matches |
| `/anything/docking` | **no match** | **matches** |
| `/anything/dockyard` | **no match** | **matches** |

When you translate an `Ingress` into a `VirtualService`, a `pathType: Prefix` of `/anything/dock` becomes an `exact` match on `/anything/dock` plus a `prefix` match on `/anything/dock/`, if you want the same behaviour.

<!-- astrona:playground:renew -->

### Send signals to the echo probe

Add two paths for the echo probe to your `Ingress`: a `Prefix` and an `Exact` one. The probe answers any path under `/anything`, so if a signal comes back `404`, the gate refused it, not the probe. Save this as `ingress-starfleet.yaml`, replacing the old file:

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

Then send one signal to each path and print the status code:

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

`/anything/docking` begins with the letters `/anything/dock`, and still gets `404`: `Prefix` compares whole pieces. `/status/200/extra` gets `404` too, because `Exact` allows nothing below the path.

### Prove the gate refused it

The probe itself would happily answer `/anything/docking`. Ask it directly from the shuttle:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://probe:8000/anything/docking
```

```text
200
```

So the `404` came from the gate. Its flight log says so:

```sh
kubectl logs -n istio-system deploy/istio-ingressgateway --tail=6 | grep -E "docking|extra"
```

You should see (lines trimmed):

```text
[2026-10-08T22:11:03.908Z] "GET /anything/docking HTTP/1.1" 404 NR route_not_found - "-" 0 0 7 - "10.244.0.6" "curl/8.7.1" "afda1c94-..." "starfleet.example.com" "-" - - 127.0.0.1:80 ...
[2026-10-08T22:11:03.932Z] "GET /status/200/extra HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.6" "curl/8.7.1" "bbee12da-..." "starfleet.example.com" "-" - - 127.0.0.1:80 ...
```

`NR` means "no route": the gate found no rule for that path, so it answered `404` itself, and the probe never saw the signal.

## What mission control builds from it

Istio does not run a separate `Ingress` program. Mission control (`istiod`) **translates** the `Ingress` into the same kind of route table that a `Gateway` with a `VirtualService` would produce, and radios it to the gate. Everything you know about reading a gate's orders still works.

### Read the translated route table

Look at the gate's route table for port `80`, and check that your namespace has no `Gateway` or `VirtualService`:

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system
kubectl get gateway,virtualservice -n starfleet
```

You should see (trimmed to the `starfleet.example.com` rows):

```text
NAME        VHOST NAME                   DOMAINS                   MATCH                         VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     PathPrefix:/anything/dock     starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     PathPrefix:/productpage       starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /status/200                   starfleet-example-com-starfleet-istio-autogenerated-k8s-ingress.starfleet
No resources found in starfleet namespace.
```

Three things to read here:

- **`PathPrefix:`** is the part-by-part `Prefix`. The `Exact` path shows as the plain path `/status/200`.
- **The `VIRTUAL SERVICE` column** names an `...-autogenerated-k8s-ingress` object. Mission control built it internally; it does not exist in Kubernetes, which is why `kubectl get virtualservice` finds nothing.
- **The order is not your order.** The rows are not listed the way you wrote the paths. The `Ingress` API has no "first rule wins" list: the most specific path wins, and the controller decides the details. If two paths overlap, you cannot see or control which one is checked first.

## Common pitfalls

> [!WARNING]
> - **Reading `Prefix` as a letter-by-letter prefix.** It compares whole pieces between `/` signs: `/anything/dock` does not match `/anything/docking`.
> - **Translating `pathType: Prefix` straight into `uri.prefix`.** The Istio version matches more. Use an `exact` match plus a `prefix` match on the path with a trailing `/`.
> - **Using `ImplementationSpecific`.** Its meaning depends on the controller, so the same file can behave differently on another one.
> - **Expecting your order of paths to decide anything.** The `Ingress` API picks the most specific path, not the first one you wrote.
> - **Blaming the backend for a `404`.** Check the gate's flight log: `404 NR` means the gate had no rule for the path.

> *`pathType: Prefix` compares whole path pieces, and Istio's `uri.prefix` compares letters. The same word means two different things in the two APIs.*
