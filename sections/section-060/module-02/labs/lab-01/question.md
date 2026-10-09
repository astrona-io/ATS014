# Question

Solve this question on: `terminal`

An application must be reachable from outside the cluster through a plain Kubernetes `Ingress`, served by Istio's ingress gateway, over both HTTP and HTTPS.

Namespace `k8s-ingress-demo` holds one application:

* `booking-service`: a Service on port 80

Istio is installed with the `demo` profile, so `istio-ingressgateway` is running in `istio-system`. There is **no `Ingress` and no `IngressClass`** anywhere in the cluster.

A self-signed certificate for `booking.ica.local` has been generated for you at **`/tmp/booking.crt`** and **`/tmp/booking.key`**.

Reach the gateway with port-forwards:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
```

Expose the application with the **plain Kubernetes `Ingress` API**: no `Gateway` and no `VirtualService`.

1.  Create a cluster-scoped `IngressClass` named **`istio`** whose `spec.controller` is exactly **`istio.io/ingress-controller`**.
2.  Create an `Ingress` named **`booking`** in `k8s-ingress-demo`, selecting that class with **`spec.ingressClassName`**.
3.  It must serve host **`booking.ica.local`** with two paths:
    *   **`/book`** with `pathType` **`Prefix`**, to `booking-service` port 80
    *   **`/status/200`** with `pathType` **`Exact`**, to `booking-service` port 80
4.  Add TLS for `booking.ica.local` using a secret named **`booking-credential`**, created from the certificate and key at `/tmp/`. Put the secret **where the gateway can actually read it**. This is the step most people get wrong.
5.  Do **not** create a `Gateway` or a `VirtualService`. The grader checks the namespace has neither.

**What the grader checks**

6.  The `IngressClass` exists with the correct controller string, and the `Ingress` reports `CLASS: istio`.
7.  `GET /book` over **HTTP** with `Host: booking.ica.local` returns **200**.
8.  `GET /book` over **HTTPS** on port 8443 returns **200**. This proves that the gateway can read the secret.
9.  `GET /booking` returns **404**. `pathType: Prefix` compares whole path elements, so `/book` must not match `/booking`.
10. `GET /status/200` returns **200** and `GET /status/200/extra` returns **404**, proving the `Exact` path type.
11. No `Gateway` and no `VirtualService` exist in `k8s-ingress-demo`.
