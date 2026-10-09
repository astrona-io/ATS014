# Claiming An Ingress

Astronaut, an `Ingress` on its own belongs to nobody. It is a docking request that no spaceport has answered yet. Some controller has to take ownership of it. This part shows how that ownership works, and what you see when nobody takes it.

## Who answers an `Ingress`

A solar system can run several ingress controllers at once: nginx, Istio, one from a cloud provider. All of them watch the same `Ingress` objects, like several spaceports that could each answer the same docking request. The **ingress class** decides which one answers.

An `Ingress` names its class in one of two ways:

| Form | Status | Looks like |
| --- | --- | --- |
| `spec.ingressClassName` | current | `ingressClassName: istio` |
| `kubernetes.io/ingress.class` annotation | older, still honoured | `kubernetes.io/ingress.class: istio` |

The annotation came first and survives in a lot of older YAML. Use the field for anything new, and recognise the annotation when you read somebody else's files. Never set both to different values: which one wins is not something to build on.

### The `IngressClass` object

`ingressClassName` points at a cluster-wide `IngressClass` object, which names the controller behind it:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
```

Two fields, each with one job:

- **`metadata.name`** is the word an `Ingress` puts in `ingressClassName`. You choose it; `istio` is only a habit.
- **`spec.controller`** is the fixed string mission control (`istiod`) looks for: **`istio.io/ingress-controller`**. Get one letter wrong and the class still exists, `Ingress` objects still point at it, and nothing serves them.

`spec.controller` cannot be changed after the object exists. To fix a wrong one, delete the `IngressClass` and create it again.

### Which gate serves it

Istio serves every `Ingress` through one gateway: the one its mesh settings `ingressService` and `ingressSelector` name. By default that is the Service `istio-ingressgateway`, with pods labelled `istio: ingressgateway`. Your playground's gateway was installed with exactly that name, so it serves `Ingress` objects without any extra setting.

There is no field on an `Ingress` to pick a different gateway. Every `Ingress` in the solar system arrives through that one gate.

## An `Ingress` nobody serves

This failure is worth seeing on purpose, because it produces no error anywhere. An `Ingress` with no class, or with a class no controller answers, is simply ignored. The object is valid, `kubectl apply` succeeds, and nothing is recorded.

<!-- astrona:playground:renew -->

### Look before you build

First check whether an ingress class or an `Ingress` already exists:

```sh
kubectl get ingressclass
kubectl get ingress -n starfleet
```

```text
No resources found
No resources found in starfleet namespace.
```

Nothing on either side. An ingress class is cluster-wide and shared by every namespace, so if an `istio` class were already there, you would use it instead of creating a second one.

### Send an `Ingress` without a class

Open the bridge's page to the outside, but leave the class out. Save this as `ingress-starfleet.yaml`:

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

Then look at the object, and send a signal to the gate:

```sh
kubectl get ingress starfleet -n starfleet
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
NAME        CLASS    HOSTS                   ADDRESS   PORTS   AGE
starfleet   <none>   starfleet.example.com             80      4s
000
```

`CLASS <none>`: no spaceport claimed the request. And the signal gets `000`: curl never got an answer at all, because the gate has no orders for port `80` yet. Kubernetes accepted the object and reports no problem.

## Claiming it

Create the class, name it in the `Ingress`, and the same rule starts working.

### Create the class and claim the `Ingress`

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

Then look at the object and send the signal again:

```sh
kubectl get ingress starfleet -n starfleet
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: starfleet.example.com" http://$GATEWAY_URL/productpage
```

```text
NAME        CLASS   HOSTS                   ADDRESS   PORTS   AGE
starfleet   istio   starfleet.example.com             80      19s
200
```

`CLASS istio` and a `200`. The rule never changed, only who was listening. `ADDRESS` stays empty on `kind`, because there is no load balancer address to show, so that column says nothing about health here.

### Read the gate's flight log

The gate keeps a flight log like every communications officer. Read its last line:

```sh
kubectl logs -n istio-system deploy/istio-ingressgateway --tail=1
```

```text
[2026-10-08T22:06:56.371Z] "GET /productpage HTTP/1.1" 200 - via_upstream - "-" 0 15068 22 22 "10.244.0.6" "curl/8.7.1" "b04d9b11-d4d7-4e12-b4a1-8512a31e5c4b" "starfleet.example.com" "10.244.0.12:9080" outbound|9080||bridge.starfleet.svc.cluster.local 10.244.0.6:43078 127.0.0.1:80 127.0.0.1:55324 - -
```

The gate received the signal for `starfleet.example.com`, chose the cluster `outbound|9080||bridge.starfleet.svc.cluster.local`, and the bridge answered `200`.

> [!TIP]
> When an `Ingress` does nothing, look at the `CLASS` column of `kubectl get ingress` before anything else. `<none>`, or a class you do not recognise, means no spaceport is serving it.

## Common pitfalls

> [!WARNING]
> - **Leaving `ingressClassName` out.** Nothing claims the `Ingress`, nothing serves it, and there is no error anywhere.
> - **A wrong `spec.controller` string.** The class exists, the `Ingress` points at it, and nothing serves it. The string must be exactly `istio.io/ingress-controller`.
> - **Trying to edit `spec.controller`.** It cannot be changed. Delete the `IngressClass` and create it again.
> - **Expecting Istio to serve an `Ingress` claimed by another controller.** Every controller sees the object, but only the one named by its class acts on it.
> - **Looking for a `Gateway` object.** Istio builds the gate's orders from the `Ingress` itself. There is no `Gateway` in your namespace to inspect.

> *An `Ingress` that no controller claims is a valid object that nothing serves. Check the `CLASS` column first.*

## Your mission: Claim The Unclaimed Ingress

You can now create an ingress class, claim an `Ingress` with it, and spot one that nobody serves. Now prove it in a graded mission: an `Ingress` points at a class that looks right, but no signal gets through the gate.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-060-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-060/module-02/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-060-02-02
astrona start ats-014-playground-060-02
```
