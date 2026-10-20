# Solution Walkthrough

The task needs two objects and a secret: an `IngressClass`, an `Ingress` and a TLS (Transport Layer Security) secret. The namespace of the secret is the real test (item 4). Everything else is ordinary Kubernetes YAML. Items 1 to 3 build the `IngressClass` and the `Ingress`. Item 4 creates the secret, and the walkthrough first shows what happens when you put it in the wrong namespace. Items 5 to 11 prove the result.

---

## Start: Set Up Access And Confirm The Starting State

The task says that no `Ingress` and no `IngressClass` exist, and that a certificate and a key are in `/tmp/`. Check this, and save the identity of the workloads. Item 11 compares against it:

```sh
kubectl get ingressclass
kubectl -n k8s-ingress-demo get ingress,gateway,virtualservice
ls /tmp/booking.crt /tmp/booking.key
kubectl -n k8s-ingress-demo get deploy,svc -o custom-columns=KIND:.kind,NAME:.metadata.name,UID:.metadata.uid
```

```text
No resources found
No resources found in k8s-ingress-demo namespace.
/tmp/booking.crt
/tmp/booking.key
KIND         NAME                 UID
Deployment   booking-service-v1   946d20b2-6a90-478e-bd53-f2f70fbcd572
Service      booking-service      7a50358a-c123-4188-a652-f9f411d2124d
```

No `IngressClass` and no `Ingress` exist yet, and the certificate and the key are on disk. `kind` has no load balancer, so you reach the ingress gateway with port forwards. You start them in the steps below, after the objects that they need exist. The ingress gateway is the Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster.

---

## Item 1: The `IngressClass`

> **Task item 1:** Create a cluster-scoped `IngressClass` named **`istio`** whose `spec.controller` is exactly **`istio.io/ingress-controller`**.

An `IngressClass` tells Kubernetes which controller serves an `Ingress`. `istiod`, the Istio control plane, is the controller that looks for the string `istio.io/ingress-controller`. If the string is wrong, the class exists and `Ingress` objects point at it, but no controller serves them. An `IngressClass` is cluster-wide, so it has no namespace. Save this as `ingressclass-istio.yaml`:

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

Check item 1:

```sh
kubectl get ingressclass istio -o jsonpath='{.spec.controller}{"\n"}'
```

```text
istio.io/ingress-controller
```

---

## Items 2 And 3: The `Ingress`

> **Task item 2:** Create an `Ingress` named **`booking`** in `k8s-ingress-demo`, selecting that class with **`spec.ingressClassName`**.
>
> **Task item 3:** It must serve host **`booking.ica.local`** with two paths:
>
> * **`/book`** with `pathType` **`Prefix`**, to `booking-service` port 80
> * **`/status/200`** with `pathType` **`Exact`**, to `booking-service` port 80

The two items describe one object. Without `ingressClassName`, no controller serves the object, and requests fail with no error. The TLS block that the next item needs is already part of the file, because item 4 names the secret. Save this as `ingress-booking.yaml`:

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

```text
ingress.networking.k8s.io/booking created
```

Check items 2 and 3. Print the `Ingress`, its class, and its paths:

```sh
kubectl -n k8s-ingress-demo get ingress booking
kubectl -n k8s-ingress-demo get ingress booking \
  -o jsonpath='{.spec.ingressClassName}{"\n"}{range .spec.rules[0].http.paths[*]}{.path}{" "}{.pathType}{" "}{.backend.service.name}{":"}{.backend.service.port.number}{"\n"}{end}'
```

```text
NAME      CLASS   HOSTS               ADDRESS   PORTS     AGE
booking   istio   booking.ica.local             80, 443   6s
istio
/book Prefix booking-service:80
/status/200 Exact booking-service:80
```

`CLASS: istio` shows that the `Ingress` names the class of Istio. If the column showed `<none>`, no controller would serve the object. The `ADDRESS` stays empty on `kind`, because there is no load balancer address to show. Do not read anything into it. The paths and their types are as the task asks.

Now start the HTTP port forward, and send a first request:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
sleep 4
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://localhost:8080/book
```

```text
200
```

HTTP already works. HTTPS does not work yet, because the secret does not exist.

---

## Item 4: The Secret In The Right Namespace

> **Task item 4:** Add TLS for `booking.ica.local` using a secret named **`booking-credential`**, created from the certificate and key at `/tmp/`. Put the secret **where the gateway can actually read it**. This is the step most people get wrong.

This step decides the task. First do what feels natural: create the secret next to the `Ingress`, in `k8s-ingress-demo`. Then start the HTTPS port forward, and test both protocols. `-k` skips the certificate check, because the certificate is self-signed. `--resolve` makes `curl` send the right host name in the TLS handshake (SNI, Server Name Indication) for a name that has no DNS entry:

```sh
kubectl -n k8s-ingress-demo create secret tls booking-credential \
  --key=/tmp/booking.key --cert=/tmp/booking.crt
sleep 5
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
sleep 4
curl -sk -o /dev/null -w '%{http_code}\n' --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://localhost:8080/book
```

```text
secret/booking-credential created
000
200
```

HTTPS returns `000`, which means that `curl` got no response, and HTTP still returns `200`. The ingress gateway runs in `istio-system`, and it reads TLS secrets only from its own namespace. A secret next to the `Ingress` is invisible to it. Nothing reports an error: the `Ingress` shows no event. HTTP works while HTTPS fails, and that pattern is the sign of this mistake. It is also why a quick HTTP test does not catch it.

Stop the HTTPS port forward with `kill %2`. Delete the wrong secret. Then create the secret in `istio-system`, and start the forward again:

```sh
kubectl -n k8s-ingress-demo delete secret booking-credential
kubectl -n istio-system create secret tls booking-credential \
  --key=/tmp/booking.key --cert=/tmp/booking.crt
sleep 8
kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 >/dev/null 2>&1 &
sleep 4
kubectl -n istio-system get secret booking-credential
curl -sk -o /dev/null -w '%{http_code}\n' --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
```

```text
secret "booking-credential" deleted from k8s-ingress-demo namespace
secret/booking-credential created
NAME                 TYPE                DATA   AGE
booking-credential   kubernetes.io/tls   2      12s
200
```

The secret has the type `kubernetes.io/tls`, so create it with `create secret tls` and not `create secret generic`. HTTPS returns `200` now.

---

## Item 6: The Class And The `Ingress`

> **Task item 6:** The `IngressClass` exists with the correct controller string, and the `Ingress` reports `CLASS: istio`.

```sh
kubectl get ingressclass
kubectl -n k8s-ingress-demo get ingress
```

```text
NAME    CONTROLLER                    PARAMETERS   AGE
istio   istio.io/ingress-controller   <none>       33s
NAME      CLASS   HOSTS               ADDRESS   PORTS     AGE
booking   istio   booking.ica.local             80, 443   33s
```

The class has the right controller, and the `Ingress` reports `CLASS: istio`.

---

## Items 7 And 8: `/book` Over HTTP And Over HTTPS

> **Task item 7:** `GET /book` over **HTTP** with `Host: booking.ica.local` returns **200**.
>
> **Task item 8:** `GET /book` over **HTTPS** on port 8443 returns **200**. This proves that the gateway can read the secret.

```sh
curl -s -o /dev/null -w 'http  /book: %{http_code}\n' -H "Host: booking.ica.local" http://localhost:8080/book
curl -sk -o /dev/null -w 'https /book: %{http_code}\n' --resolve booking.ica.local:8443:127.0.0.1 https://booking.ica.local:8443/book
```

```text
http  /book: 200
https /book: 200
```

Both protocols return `200`.

---

## Items 9 And 10: The Two Path Types

> **Task item 9:** `GET /booking` returns **404**. `pathType: Prefix` compares whole path elements, so `/book` must not match `/booking`.
>
> **Task item 10:** `GET /status/200` returns **200** and `GET /status/200/extra` returns **404**, proving the `Exact` path type.

The two path types behave differently, and the task checks the edge of each one:

```sh
for uri in /book /book/123 /booking /status/200 /status/200/extra; do
  printf '%-20s -> ' "$uri"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" "http://localhost:8080$uri"
done
```

```text
/book                -> 200
/book/123            -> 200
/booking             -> 404
/status/200          -> 200
/status/200/extra    -> 404
```

The path `/booking` starts with the characters `/book`, and it does not match. `pathType: Prefix` splits the path at each `/` and compares whole elements, and the element here is `booking`, not `book`. If you wrote the same rule as an Istio `VirtualService` with `uri: { prefix: /book }`, `/booking` would return `200`, because the `prefix` of Istio compares characters. The same word means different things in the two APIs, and that difference breaks routes quietly during a migration. The path `/status/200/extra` returns `404`, which shows that `Exact` matches nothing below its path.

---

## Item 5 And Item 11: No `Gateway` And No `VirtualService`

> **Task item 5:** Do **not** create a `Gateway` or a `VirtualService`. The grader checks the namespace has neither.
>
> **Task item 11:** No `Gateway` and no `VirtualService` exist in `k8s-ingress-demo`.

Check that the namespace has neither object. Then read the route table of the HTTP listener of the gateway. The flag `--name http.8080` shows only that table:

```sh
kubectl -n k8s-ingress-demo get gateway,virtualservice
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system --name http.8080
```

```text
No resources found in k8s-ingress-demo namespace.
NAME          VHOST NAME               DOMAINS               MATCH                VIRTUAL SERVICE
http.8080     booking.ica.local:80     booking.ica.local     /status/200          booking-ica-local-booking-istio-autogenerated-k8s-ingress.k8s-ingress-demo
http.8080     booking.ica.local:80     booking.ica.local     PathPrefix:/book     booking-ica-local-booking-istio-autogenerated-k8s-ingress.k8s-ingress-demo
```

Both paths are in the route table of the gateway, and there is no `Gateway` and no `VirtualService` in the namespace. `istiod` translated the `Ingress` into the same kind of configuration that those objects would produce. The column `VIRTUAL SERVICE` shows the name of the generated configuration, which ends in `istio-autogenerated-k8s-ingress`. The column `MATCH` shows `PathPrefix:/book` and not `/book*`: the gateway compares whole path elements, as items 9 and 10 showed.

The workloads did not change either. Run the identity command from the Start section again, and the output is the same:

```sh
kubectl -n k8s-ingress-demo get deploy,svc -o custom-columns=KIND:.kind,NAME:.metadata.name,UID:.metadata.uid
```

```text
KIND         NAME                 UID
Deployment   booking-service-v1   946d20b2-6a90-478e-bd53-f2f70fbcd572
Service      booking-service      7a50358a-c123-4188-a652-f9f411d2124d
```

Stop the port forwards with `kill %1 %2` when you are done.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-060/module-02/labs/lab-01
```

The grader sends requests through the gateway over HTTP and HTTPS, and checks the namespace.

---

## Mistakes That Fail The Grader

- **The secret in the application namespace (item 4).** HTTPS never comes up while HTTP keeps working, and nothing reports an error. This is the most common failure here.
- **A wrong `spec.controller` (item 1).** It must be `istio.io/ingress-controller` exactly.
- **Leaving out `ingressClassName` (item 2).** The `CLASS` column shows `<none>`, nothing serves the object, and requests fail with no error.
- **Reading `pathType: Prefix` as a character prefix (item 9).** The path `/book` does not match `/booking`.
- **Using `pathType: Prefix` for `/status/200` (item 10).** It would match `/status/200/extra` too.
- **Creating a `Gateway` or a `VirtualService` as well (items 5 and 11).** The grader checks that neither exists.
- **Creating the secret with `create secret generic` (item 4).** It must have the type `kubernetes.io/tls`.
- **Testing HTTPS without `--resolve` (item 8).** The host name has no DNS entry, and the SNI name has to match the certificate.
