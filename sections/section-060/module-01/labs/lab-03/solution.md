# Solution Walkthrough

Mission debrief, astronaut. The gate was open, but three mistakes stood between it and the bridge: a flight plan not linked to the gate, a typo in the gate's host, and a route to a ship that does not exist. Fixing them one at a time lets each answer from the gate point at the next fault.

---

## Step 1: Confirm the failure

Start the port forward and send one signal through the gate, then read the gate's flight log:

```sh
kubectl -n istio-ingress port-forward svc/istio-ingress 8080:80 >/dev/null 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
kubectl logs -n istio-ingress deploy/istio-ingress --tail=1
```

```text
404
[2026-10-08T22:18:27.781Z] "GET /productpage HTTP/1.1" 404 NR route_not_found - "-" 0 0 0 - "10.244.0.6" "curl/8.7.1" "6c8d70e1-91f0-4d01-8629-4071d0fd7ab7" "starfleet.example.com" "-" - - 127.0.0.1:80 127.0.0.1:39168 - -
```

A `404` with the flag `NR` ("no route"). The gate has a listener, so the `Gateway` selector works. But no route matched, so look at the flight plan and the hosts. If you get `000` right after starting the port forward, wait a few seconds and send the signal again.

## Step 2: Look at the objects and the gate's route table

```sh
kubectl get gateway,virtualservice -n starfleet
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress
```

```text
NAME                                            AGE
gateway.networking.istio.io/starfleet-gateway   2m31s

NAME                                        GATEWAYS   HOSTS                       AGE
virtualservice.networking.istio.io/bridge              ["starfleet.example.com"]   2m31s
NAME        VHOST NAME       DOMAINS     MATCH                  VIRTUAL SERVICE
http.80     blackhole:80     *           /*                     404
            backend          *           /stats/prometheus*     
            backend          *           /healthz/ready*        
```

The `GATEWAYS` column of the flight plan is empty: it has no `gateways:` field, so its routes go to `mesh` (the sidecars) and never reach the gate. The gate's route table confirms it: only `blackhole:80`, which answers `404` to everything.

## Step 3: Ask `istioctl analyze`

```sh
istioctl analyze -n starfleet
```

```text
Error [IST0101] (VirtualService starfleet/bridge) Referenced host not found: "bridges"
```

(The `analyze` output is trimmed to its finding.)

A second fault: the flight plan sends signals to `bridges`, but the ship is called `bridge`. `istioctl analyze` does not report the missing `gateways:` field, because a flight plan for `mesh` is a valid object.

## Step 4: Link the flight plan to the gate

Fix one thing at a time, so each answer from the gate tells you what is left. Start with the link: add `gateways:` and leave the destination as it is for now. Save this as `virtualservice-bridge.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridges
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
istioctl analyze -n starfleet
```

```text
404
Error [IST0101] (VirtualService starfleet/bridge) Referenced host not found: "bridges"
Warning [IST0132] (VirtualService starfleet/bridge) one or more host [starfleet.example.com] defined in VirtualService starfleet/bridge not found in Gateway starfleet/starfleet-gateway.
```

(The `analyze` output is trimmed to its findings.)

Still `404`, but now `istioctl analyze` shows the third fault. `IST0132` says the gate does not serve `starfleet.example.com`. Read the `Gateway`'s host letter by letter: `kubectl get gateway starfleet-gateway -n starfleet -o jsonpath='{.spec.servers[0].hosts}'` shows `starfleet.exmaple.com`.

## Step 5: Fix the gate's host

Save this as `gateway-starfleet.yaml`:

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

Then check the result:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
kubectl logs -n istio-ingress deploy/istio-ingress --tail=1
```

```text
503
[2026-10-08T22:17:44.825Z] "GET /productpage HTTP/1.1" 503 NC cluster_not_found - "-" 0 0 2 - "10.244.0.6" "curl/8.7.1" "cb33cab9-81c0-4a0e-8697-77f7bf1ca264" "starfleet.example.com" "-" - - 127.0.0.1:80 127.0.0.1:59728 - -
```

The answer moved from `404` to `503`. Routing works now: a route matched. But its destination does not exist, so the log shows `NC cluster_not_found`. That is the `bridges` typo.

## Step 6: Point the route at the real bridge

In `virtualservice-bridge.yaml`, change `host: bridges` to `host: bridge`. The file now looks like this:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: bridge
  namespace: starfleet
spec:
  hosts:
  - starfleet.example.com
  gateways:
  - starfleet-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        prefix: /static
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: bridge
        port:
          number: 9080
```

Apply it:

```sh
kubectl apply -f virtualservice-bridge.yaml
```

```text
virtualservice.networking.istio.io/bridge configured
```

Then check the result: both bridge paths, a path that is not in the flight plan, a host the gate does not serve, and `istioctl analyze`:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/productpage
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/api/v1/products
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: starfleet.example.com" http://localhost:8080/admin
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: other.example.com" http://localhost:8080/productpage
istioctl analyze -n starfleet
```

```text
200
200
404
404
✔ No validation issues found when analyzing namespace: starfleet.
```

## Step 7: Check the gate's own configuration

```sh
istioctl proxy-config routes deploy/istio-ingress -n istio-ingress | grep -E "NAME|starfleet"
istioctl proxy-config endpoints deploy/istio-ingress -n istio-ingress --cluster "outbound|9080||bridge.starfleet.svc.cluster.local"
```

```text
NAME        VHOST NAME                   DOMAINS                   MATCH                  VIRTUAL SERVICE
http.80     starfleet.example.com:80     starfleet.example.com     /productpage           bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /static*               bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /login                 bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /logout                bridge.starfleet
http.80     starfleet.example.com:80     starfleet.example.com     /api/v1/products*      bridge.starfleet
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.12:9080     HEALTHY     OK                outbound|9080||bridge.starfleet.svc.cluster.local
```

The gate holds your routes for `starfleet.example.com`, from `bridge.starfleet`, and the bridge has a healthy ship behind it. The ship's address changes with every run.

## Mistakes that fail the grader

- **Setting `hosts: ["*"]` on the `Gateway` to get around the typo.** The gate must serve only `starfleet.example.com`.
- **Creating a Service called `bridges` to match the typo.** The grader checks that no such Service exists and that every route goes to `bridge` on port `9080`.
- **Adding a catch-all route.** `/admin` must still get `404`.
- **Leaving out `/api/v1/products`.** The grader checks that it gets `200` too.
- **Renaming the objects or changing the gateway pods' labels.** The grader looks for `starfleet-gateway` and `bridge` in `starfleet`, and for gateway pods labelled `istio=ingress`.
