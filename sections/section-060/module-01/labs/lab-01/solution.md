# Solution Walkthrough

Three objects: one listener (the gate), two route sets (the flight plans). The field that decides whether any of it works is one line long.

---

## Step 1: Set Up Access And See the Starting State

`kind` has no load balancer, so the gateway's `EXTERNAL-IP` will never be assigned. Port-forward instead:

```sh
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
export GATEWAY_URL=localhost:8080

kubectl -n istio-system get pods -l istio=ingressgateway
kubectl -n ingress-demo get gateway,virtualservice
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
NAME                                    READY   STATUS    AGE
istio-ingressgateway-6d9c5b8f7c-4kx2n   1/1     Running   6m
No resources found in ingress-demo namespace.
404
```

The pod is `1/1` — a standalone proxy, no application container. It is healthy and reachable and answers 404 because nothing has configured it.

---

## Step 2: Open the Listener

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > gateway-public-gateway.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: public-gateway
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
        - catalog.ica.local
EOF
kubectl apply -f gateway-public-gateway.yaml
```

```text
gateway.networking.istio.io/public-gateway created
```

Three things the grader checks here:

- **`selector: istio: ingressgateway`** — a pod label selector, matching the gateway the `demo` profile installed. A selector matching nothing produces an object that configures no proxy.
- **`protocol: HTTP`** — this is what gives you host and path routing. `TCP` would give a byte pipe that silently ignores every rule you write.
- **Both hosts listed, and no `*`.** The task requires the listener to reject unknown hosts, so a wildcard fails check 7.

Note the `Gateway` lives in `ingress-demo` while the pod it configures lives in `istio-system`. That split is normal.

Confirm the listener exists — and that it still serves nothing:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: booking.ica.local" http://$GATEWAY_URL/book
```

```text
404
```

Expected. A listener with no routes attached serves nothing.

---

## Step 3: Attach Both Route Sets

```sh
cat > booking-manifests.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: ingress-demo
spec:
  hosts:
    - booking.ica.local
  gateways:
    - public-gateway
  http:
    - match:
        - uri:
            prefix: /book
      route:
        - destination:
            host: booking-service
            port:
              number: 80
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: catalog
  namespace: ingress-demo
spec:
  hosts:
    - catalog.ica.local
  gateways:
    - public-gateway
  http:
    - match:
        - uri:
            prefix: /items
      route:
        - destination:
            host: catalog-service
            port:
              number: 80
EOF
kubectl apply -f booking-manifests.yaml
istioctl analyze -n ingress-demo
```

```text
virtualservice.networking.istio.io/booking created
virtualservice.networking.istio.io/catalog created
✔ No validation issues found when analyzing namespace: ingress-demo.
```

**`gateways: [public-gateway]` is the whole exercise.** Omit it and the routes attach to `mesh` — sidecars only — the gateway keeps returning 404, and `istioctl analyze` stays perfectly clean because an unbound `VirtualService` is a valid object.

Note also that each `VirtualService` names only its own host. Both attach to the same listener; the listener's host list and the route's host list are what keep them separate.

---

## Step 4: Confirm the Routes Reached the Gateway

This is the check that distinguishes "my routes are wrong" from "my routes are not there":

```sh
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system | grep -E 'booking|catalog'
```

```text
http.8080   booking.ica.local   /book*    booking.ingress-demo
http.8080   catalog.ica.local   /items*   catalog.ingress-demo
```

Both hosts, with their path matches and the `VirtualService` that produced each. If a host is missing here, its `VirtualService` never attached.

---

## Step 5: Verify All Four Cases

```sh
for t in "booking.ica.local /book" "catalog.ica.local /items" \
         "unknown.ica.local /book" "catalog.ica.local /book"; do
  set -- $t
  printf '%-20s %-8s -> ' "$1" "$2"
  curl -s -o /dev/null -w '%{http_code}\n' -H "Host: $1" "http://$GATEWAY_URL$2"
done
```

```text
booking.ica.local    /book    -> 200
catalog.ica.local    /items   -> 200
unknown.ica.local    /book    -> 404
catalog.ica.local    /book    -> 404
```

The last two are the interesting ones and they fail for different reasons. `unknown.ica.local` matched **no listener host**, so the gateway had nowhere to send it. `catalog.ica.local /book` matched the listener fine but found **no route** for that path under that host — the `catalog` `VirtualService` only knows `/items`.

Both are 404, which is why the route dump in step 4 matters: the status code alone cannot tell them apart.

---

## Common Mistakes

- **Omitting `gateways:`.** The routes attach to `mesh`, the gateway 404s, and nothing reports an error. The single most common failure here.
- **`hosts: ["*"]` on the `Gateway`.** Convenient, and it fails the "unknown host must be rejected" check.
- **One `VirtualService` listing both hosts.** It would work for traffic, but then `/book` and `/items` are both reachable under both hostnames — check 8 fails.
- **`protocol: TCP`.** No host or path routing at all.
- **A `selector` that matches nothing.** The `Gateway` exists and configures no proxy; `istioctl analyze` catches this one.
- **Forgetting `-H "Host: ..."` when testing.** Without it curl sends `localhost:8080`, which matches no listener host.
- **Expecting `EXTERNAL-IP` to be assigned.** `<pending>` is correct on `kind`.
- **Referencing the gateway as `istio-system/public-gateway`.** The `Gateway` object is in `ingress-demo`, so the bare name is right here — a namespace prefix would point at nothing.
