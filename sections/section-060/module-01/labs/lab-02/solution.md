# Solution Walkthrough

Mission debrief, astronaut. The flight plan was right all along. The `Gateway` asked for gateway pods with a label that no pod carries, so no gateway ever opened a listener.

---

## Step 1: Confirm the failure

Start the port forward and send one signal through the gate:

```sh
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
```

```text
000
```

`000` means curl got no reply at all. That points at the gate itself, not at the flight plan: nothing is listening on port `80`. A missing route would give `404` instead.

## Step 2: Compare the selector with the gateway pod

Read the gateway pod's `istio` label, then the `Gateway`'s selector:

```sh
kubectl get pods -n istio-ingress -L istio
kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME                             READY   STATUS    RESTARTS   AGE   ISTIO
istio-ingress-5f768fb4b6-lgxmt   1/1     Running   0          75s   ingress
{"istio":"ingressgateway"}
```

The pod carries `istio=ingress`. The `Gateway` asks for `istio=ingressgateway`, the label of an `istioctl` install. This Helm install does not use it.

## Step 3: Let the tools confirm it

Ask `istioctl analyze` and the gateway's own listeners:

```sh
istioctl analyze -n starfleet
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress
```

```text
Error [IST0101] (Gateway starfleet/starfleet-gateway) Referenced selector not found: "istio=ingressgateway"
ADDRESSES PORT  MATCH DESTINATION
0.0.0.0   15021 ALL   Inline Route: /healthz/ready*
0.0.0.0   15090 ALL   Inline Route: /stats/prometheus*
```

(The `analyze` output is trimmed to its finding.)

`IST0101` names the selector that matches nothing. The listener list has only the gateway's health and metrics ports, and no port `80`.

## Step 4: Fix the selector

Keep everything else in the `Gateway` the same. Save this as `gateway-starfleet.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: starfleet-gateway
  namespace: starfleet
spec:
  selector:
    istio: ingress
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - starfleet.example.com
```

Apply it:

```sh
kubectl apply -f gateway-starfleet.yaml
```

```text
gateway.networking.istio.io/starfleet-gateway configured
```

Then check the result in the gateway's proxy:

```sh
istioctl proxy-config listener deploy/istio-ingress -n istio-ingress --port 80
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress | grep -E "NAME|starfleet"
```

```text
ADDRESSES PORT MATCH DESTINATION
0.0.0.0   80   ALL   Route: http.80
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     /productpage           bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /static*               bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /login                 bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /logout                bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /api/v1/products*      bridge.starfleet
```

The port `80` listener is open, and its route table holds the bridge's flight plan. The flight plan was already linked to `starfleet-gateway`; it only needed a gate that really opened.

## Step 5: Prove it with live signals

Send a signal for the bridge, and one for a host the gate does not serve:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: other.example.com" http://localhost:8080/productpage
istioctl analyze -n starfleet
```

```text
200
404
✔ No validation issues found when analyzing namespace: starfleet.
```

The bridge answers through the gate, other hosts are still not served, and `istioctl analyze` is clean.

## Mistakes that fail the grader

- **Changing the gateway pods' labels to match the `Gateway`.** The grader checks that the `istio-ingress` Deployment still labels its pods `istio=ingress`. Fix the `Gateway`, not the gateway.
- **Setting `hosts: ["*"]`.** The gate must serve only `starfleet.example.com`. The grader fails with `the Gateway hosts are [*]`.
- **Editing the `VirtualService`.** It was correct. The grader checks that it still serves `starfleet.example.com`, links to `starfleet-gateway` and routes to `bridge` on port `9080`.
- **Renaming the `Gateway` or moving it to another namespace.** The flight plan links to `starfleet-gateway` in `starfleet` by its bare name.
