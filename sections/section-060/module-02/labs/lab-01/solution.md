# Solution Walkthrough

Two objects and a secret. The secret is the exercise — everything else is ordinary Kubernetes YAML.

---

## Step 1: Set Up Access And Confirm the Starting State

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

Nothing exists yet, and the key pair is waiting.

---

## Step 2: Create the IngressClass

```sh
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: istio
spec:
  controller: istio.io/ingress-controller
EOF
```

```text
ingressclass.networking.k8s.io/istio created
```

`spec.controller` must be **exactly** `istio.io/ingress-controller`. The `metadata.name` is arbitrary — `istio` is convention — but the controller string is the identifier `istiod` watches for. Get it wrong and the class exists, `Ingress` objects reference it happily, and nothing implements them.

The object is cluster-scoped, so there is no namespace on it.

---

## Step 3: Create the Ingress

```sh
kubectl apply -f - <<'EOF'
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
EOF
kubectl -n k8s-ingress-demo get ingress booking
```

```text
ingress.networking.k8s.io/booking created
NAME      CLASS   HOSTS               ADDRESS   PORTS     AGE
booking   istio   booking.ica.local             80, 443   4s
```

`CLASS: istio` is the claim. If that column read `<none>`, nothing would be serving the object and the requests below would 404 with no error anywhere.

`ADDRESS` stays empty on `kind` — there is no load balancer address to publish — so do not read anything into it.

HTTP already works:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
200
```

HTTPS does not, because the secret does not exist yet.

---

## Step 4: Create the Secret — In the Right Namespace

This is the step that decides the task.

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

**`-n istio-system`, not `-n k8s-ingress-demo`.** The `Ingress` lives with the application; the gateway *pod* lives in `istio-system`, and a pod can only read secrets from its own namespace. Put the secret beside the `Ingress` and you get:

```text
000
```

— with HTTP still returning 200 the whole time, no event on the `Ingress`, and nothing in its status. That asymmetry is the signature, and it is why this mistake survives a casual test.

`-k` skips verification because the certificate is self-signed; `--resolve` makes curl send the correct SNI and `Host` for a name that resolves nowhere.

---

## Step 5: Verify the Path Types

The two path types behave differently, and the grader checks both boundaries:

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

`/booking` is the interesting one. It starts with the characters `/book` and it does **not** match, because `pathType: Prefix` splits on `/` and compares element by element — the element is `booking`, not `book`.

Write the same rule as an Istio `VirtualService` with `uri: { prefix: /book }` and `/booking` **would** return 200, because Istio's `prefix` is a plain string prefix. Same word, two APIs, different semantics — and it is exactly the kind of thing that breaks quietly during a migration.

`/status/200/extra` failing confirms `Exact` does not match below itself.

---

## Step 6: Confirm the Translation

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep booking
kubectl -n k8s-ingress-demo get gateway,virtualservice
```

```text
http.8080   booking.ica.local   /book*   booking-service.k8s-ingress-demo
No resources found in k8s-ingress-demo namespace.
```

The route is in the gateway's table and there is no `Gateway` and no `VirtualService` anywhere — `istiod` translated the `Ingress` into the same internal configuration those objects would have produced. Compare that route line with module 1's: nearly identical, arrived at from a different API.

---

## Common Mistakes

- **Secret in the application namespace.** HTTPS silently never comes up while HTTP keeps working. The single most common failure here.
- **Wrong `spec.controller`.** It must be `istio.io/ingress-controller` exactly.
- **Omitting `ingressClassName`.** `CLASS: <none>`, nothing serves the object, 404 with no error.
- **Reading `pathType: Prefix` as a string prefix.** `/book` does not match `/booking`.
- **Using `pathType: Prefix` for `/status/200`.** It would match `/status/200/extra` and fail check 10.
- **Creating a `Gateway` or `VirtualService` to "help".** The grader checks neither exists.
- **Creating the secret with `create secret generic`.** It must be type `kubernetes.io/tls`; use `create secret tls`.
- **Testing HTTPS without `--resolve`.** The hostname resolves nowhere, and SNI has to match the certificate.
