# Solution Walkthrough

The task needs two objects and a secret: an `IngressClass`, an `Ingress` and a TLS (Transport Layer Security) secret. The secret's namespace is the real test. Everything else is ordinary Kubernetes YAML.

---

## Step 1: Set Up Access And Confirm the Starting State

Forward local ports `8080` and `8443` to the ingress gateway, then check that nothing exists yet:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80  >/dev/null 2>&1 &
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080

kubectl get ingressclass
kubectl -n k8s-ingress-demo get ingress,gateway,virtualservice
ls -l /tmp/booking.crt /tmp/booking.key
```

```text
No resources found
No resources found in k8s-ingress-demo namespace.
-rw-r--r-- 1 root root 1188 /tmp/booking.crt
-rw------- 1 root root 1704 /tmp/booking.key
```

No `IngressClass` and no `Ingress` exist yet, and the certificate and key are on disk.

---

## Step 2: Create the IngressClass

Write the manifest to a file and apply the file. This habit pays off in the exam: you can read the file again, edit it and apply it again.

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

`spec.controller` must be **exactly** `istio.io/ingress-controller`. You can choose any `metadata.name` (`istio` is only a habit), but the controller string is the value that `istiod`, Istio's control plane, looks for. If the string is wrong, the class exists and `Ingress` objects point at it, but no controller serves them.

An `IngressClass` is cluster-wide, so it has no namespace.

---

## Step 3: Create the Ingress

Save this as `ingress-booking.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: booking
  namespace: k8s-ingress-demo
spec:
  ingressClassName: istio
  tls:
    - hosts:
        - booking.ica.local
      secretName: booking-credential
  rules:
    - host: booking.ica.local
      http:
        paths:
          - path: /book
            pathType: Prefix
            backend:
              service:
                name: booking-service
                port:
                  number: 80
          - path: /status/200
            pathType: Exact
            backend:
              service:
                name: booking-service
                port:
                  number: 80
```

Apply it:

```sh
kubectl apply -f ingress-booking.yaml
```

Then check the result:

```sh
kubectl -n k8s-ingress-demo get ingress booking
```

```text
ingress.networking.k8s.io/booking created
NAME      CLASS   HOSTS               ADDRESS   PORTS     AGE
booking   istio   booking.ica.local             80, 443   4s
```

`CLASS: istio` shows that the `Ingress` names Istio's class. If the column showed `<none>`, no controller would serve the object, and the requests below would fail with no error anywhere.

`ADDRESS` stays empty on `kind`, because there is no load balancer address to show. Do not read anything into it.

HTTP already works:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
200
```

HTTPS does not work yet, because the secret does not exist.

---

## Step 4: Create the Secret in the Right Namespace

This step decides the task. Create the secret in `istio-system` and test HTTPS:

```sh
kubectl -n istio-system create secret tls booking-credential \
  --key=/tmp/booking.key --cert=/tmp/booking.crt
sleep 5
curl -sk -o /dev/null -w '%{http_code}\n' \
  --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
```

```text
secret/booking-credential created
200
```

**Use `-n istio-system`, not `-n k8s-ingress-demo`.** The `Ingress` lives next to the application, but the ingress gateway runs in `istio-system`. The gateway is the component that loads the certificate, and it reads TLS secrets only from its own namespace. If you put the secret next to the `Ingress`, the HTTPS request returns:

```text
000
```

HTTP still returns 200 the whole time, and the `Ingress` shows no event and nothing in its status. HTTP works while HTTPS fails: that pattern is the sign of this mistake, and it is why a quick HTTP test does not catch it.

`-k` skips certificate verification, because the certificate is self-signed. `--resolve` makes curl send the correct SNI (Server Name Indication, the host name in the TLS handshake) and `Host` header for a name that has no DNS (Domain Name System) entry.

---

## Step 5: Verify the Path Types

The two path types behave differently, and the grader checks the edge of each one:

```sh
for p in /book /book/123 /booking /status/200 /status/200/extra; do
  printf '%-20s -> ' "$p"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" "http://$GATEWAY_URL$p"
done
```

```text
/book                -> 200
/book/123            -> 200
/booking             -> 404
/status/200          -> 200
/status/200/extra    -> 404
```

`/booking` is the interesting one. It starts with the characters `/book`, and it does **not** match. `pathType: Prefix` splits the path at each `/` and compares whole elements, and the element here is `booking`, not `book`.

If you write the same rule as an Istio `VirtualService` with `uri: { prefix: /book }`, `/booking` **would** return 200, because Istio's `prefix` compares characters. The same word means different things in the two APIs, and this difference breaks routes quietly during a migration.

`/status/200/extra` returns 404, which confirms that `Exact` matches nothing below its path.

---

## Step 6: Confirm the Translation

Check that the route reached the gateway, and that no Istio routing objects exist in the namespace:

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep booking
kubectl -n k8s-ingress-demo get gateway,virtualservice
```

```text
http.8080   booking.ica.local   /book*   booking-service.k8s-ingress-demo
No resources found in k8s-ingress-demo namespace.
```

The route is in the gateway's route table, and there is no `Gateway` and no `VirtualService` anywhere. `istiod` translated the `Ingress` into the same kind of configuration those objects would produce. A `Gateway` with a `VirtualService` would give an almost identical route line.

---

## Common Mistakes

- **Secret in the application namespace.** HTTPS never comes up while HTTP keeps working, and nothing reports an error. This is the most common failure here.
- **Wrong `spec.controller`.** It must be `istio.io/ingress-controller` exactly.
- **Leaving out `ingressClassName`.** The `CLASS` column shows `<none>`, nothing serves the object, and requests fail with no error.
- **Reading `pathType: Prefix` as a character prefix.** `/book` does not match `/booking`.
- **Using `pathType: Prefix` for `/status/200`.** It would match `/status/200/extra` and fail check 10.
- **Creating a `Gateway` or `VirtualService` as well.** The grader checks that neither exists.
- **Creating the secret with `create secret generic`.** It must be type `kubernetes.io/tls`; use `create secret tls`.
- **Testing HTTPS without `--resolve`.** The host name has no DNS entry, and the SNI name has to match the certificate.
