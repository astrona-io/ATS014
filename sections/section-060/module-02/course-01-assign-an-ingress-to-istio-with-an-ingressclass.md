# Assign An Ingress To Istio With An IngressClass

A Kubernetes `Ingress` is an object that describes how HTTP (Hypertext Transfer Protocol) requests from outside the cluster reach a Service inside it. On its own, an `Ingress` does nothing. An ingress controller, a program that reads `Ingress` objects and configures a proxy from them, has to take it. This part shows how Istio becomes that controller, and what you see when no controller takes an `Ingress`.

## Which controller serves an `Ingress`

A cluster can run several ingress controllers at the same time, for example nginx, Istio and one from a cloud provider. All of them watch the same `Ingress` objects. The ingress class decides which controller acts on a given `Ingress`.

An `Ingress` names its class in one of two ways:

| Form | Status | Looks like |
| --- | --- | --- |
| `spec.ingressClassName` | current | `ingressClassName: istio` |
| `kubernetes.io/ingress.class` annotation | older, still honoured | `kubernetes.io/ingress.class: istio` |

The annotation came first, and a lot of older YAML still uses it. Use the field for anything new, and recognise the annotation when you read other people's files. Never set both to different values, because you cannot rely on which one wins.

### The `IngressClass` object

The `ingressClassName` field points at an `IngressClass`. An `IngressClass` is a cluster-wide object that names the controller behind a class:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Each of the two fields has one job:

- **`metadata.name`** is the word an `Ingress` puts in `ingressClassName`. You choose it; `istio` is only a habit.
- **`spec.controller`** is the fixed string that `istiod` looks for: **`istio.io/ingress-controller`**. `istiod` is Istio's control plane: it turns Kubernetes and Istio objects into proxy configuration and sends that configuration to every proxy. If one letter in the string is wrong, the class still exists and `Ingress` objects still point at it, but `istiod` serves none of them.

You cannot change `spec.controller` after the object exists. To fix a wrong value, delete the `IngressClass` and create it again.

### Which gateway serves it

An ingress gateway is an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. Istio serves every `Ingress` through one ingress gateway: the one that the mesh settings `ingressService` and `ingressSelector` name. By default, that is the Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`.

The playground installs its gateway with exactly that name, so it serves `Ingress` objects with no extra setting. An `Ingress` has no field to pick a different gateway. Every `Ingress` in the cluster goes through that one gateway.

## An `Ingress` that no controller serves

This failure is worth seeing on purpose, because it produces no error anywhere. Kubernetes accepts an `Ingress` with no class, or with a class that no controller answers, as a valid object. But no controller acts on it, so no proxy gets a route for it.

All the commands in this part send requests to the gateway through `$GATEWAY_URL`. Set it in your terminal first if you have not done so yet: `GATEWAY_URL=localhost:8080`. The playground forwards that local port to port `80` of the gateway.

<!-- astrona:playground:renew -->

Before you create anything, check whether an ingress class or an `Ingress` already exists:

```sh
kubectl get ingressclass
kubectl get ingress -n starfleet
```

```text
No resources found
No resources found in starfleet namespace.
```

Neither exists. An ingress class is cluster-wide and every namespace shares it. If an `istio` class were already there, you would use it instead of creating a second one.

Now expose the `bridge` page to the outside, but leave the class out. Save this as `ingress-starfleet.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: starfleet
  namespace: starfleet
spec:
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
```

Apply it:

```sh
kubectl apply -f ingress-starfleet.yaml
```

```text
ingress.networking.k8s.io/starfleet created
```

Then check the object, and send a request to the gateway:

```sh
kubectl get ingress starfleet -n starfleet
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
NAME        CLASS    HOSTS                   ADDRESS   PORTS   AGE
starfleet   <none>   starfleet.example.com             80      4s
000
```

The `CLASS` column shows `<none>`: no controller took the `Ingress`. The request gets `000`, which means curl got no response at all. The gateway has no listener on port `80` yet, because `istiod` has sent it no configuration for that port. Kubernetes accepted the object and reports no problem.

## Assign the `Ingress` to Istio

To fix this, create the class and name it in the `Ingress`. The same rule then starts to work.

Save this as `ingressclass-istio.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Apply it:

```sh
kubectl apply -f ingressclass-istio.yaml
```

```text
ingressclass.networking.k8s.io/istio created
```

Now add the class to the `Ingress`. Save this as `ingress-starfleet.yaml`, replacing the old file:

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
```

Apply it:

```sh
kubectl apply -f ingress-starfleet.yaml
```

Then check the result:

```sh
kubectl get ingress starfleet -n starfleet
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
NAME        CLASS   HOSTS                   ADDRESS   PORTS   AGE
starfleet   istio   starfleet.example.com             80      19s
200
```

The `CLASS` column shows `istio`, and the request gets `200`. The rule did not change; only the controller that reads it changed. The `ADDRESS` column stays empty on `kind`, because there is no load balancer address to show. So that column tells you nothing about health here.

The gateway writes an access log line for every request, so you can see which Service answered. Read its last line:

```sh
kubectl logs -n istio-system deploy/istio-ingressgateway --tail=1
```

```text
[2026-10-08T22:06:56.371Z] "GET /productpage HTTP/1.1" 200 - via_upstream - "-" 0 15068 22 22 "10.244.0.6" "curl/8.7.1" "b04d9b11-d4d7-4e12-b4a1-8512a31e5c4b" "starfleet.example.com" "10.244.0.12:9080" outbound|9080||bridge.starfleet.svc.cluster.local 10.244.0.6:43078 127.0.0.1:80 127.0.0.1:55324 - -
```

The gateway received the request for `starfleet.example.com` and picked the cluster `outbound|9080||bridge.starfleet.svc.cluster.local`. A cluster, in Envoy's words, is a group of endpoints that a request can go to. The `bridge` pod then answered with `200`.

> [!TIP]
> When an `Ingress` does nothing, look at the `CLASS` column of `kubectl get ingress` first. Then run `kubectl get ingressclass` and check the `CONTROLLER` column. The `CLASS` column only repeats the class name; it does not prove that a controller serves that class.

You now know that an `Ingress` is served only when its class points at the controller string `istio.io/ingress-controller`, and that a missing or wrong class fails without any error. The open question is how the gateway decides which paths match a rule, which is not the same as in Istio's own routing objects.

## Common pitfalls

> [!WARNING]
> - **Leaving `ingressClassName` out.** No controller takes the `Ingress`, nothing serves it, and there is no error anywhere.
> - **A wrong `spec.controller` string.** The class exists and the `Ingress` points at it, but `istiod` serves nothing. The string must be exactly `istio.io/ingress-controller`.
> - **Trying to edit `spec.controller`.** Kubernetes refuses the change. Delete the `IngressClass` and create it again.
> - **Expecting Istio to serve an `Ingress` that names another controller's class.** Every controller sees the object, but only the one its class names acts on it.
> - **Looking for a `Gateway` object.** `istiod` builds the gateway's configuration from the `Ingress` itself. There is no `Gateway` in your namespace to inspect.

## Your mission: Fix An IngressClass That No Controller Serves

You can now create an ingress class, assign an `Ingress` to Istio with it, and spot an `Ingress` that no controller serves. The mission gives you an `Ingress` that points at a class that looks right, while no request gets through the gateway, and asks you to fix the class.

The mission runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-02
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-02
```

When you have finished, remove the mission and start your playground again:

```sh
astrona destroy ats-014-lab-060-02-02
astrona start ats-014-playground-060-02
```
