# Overview: Expose A Service With An Istio Ingress Gateway (Playground)

This is a playground, not a lab. It starts a fresh cluster, installs Istio, an ingress gateway and the sample application, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, run `astrona destroy`, and start again.

In this playground, requests come from outside the cluster. They enter the mesh through the ingress gateway: an Envoy proxy at the edge of the mesh that accepts traffic from outside the cluster. You configure it with a `Gateway` object, which opens a listener on the gateway pods, and a `VirtualService` bound to that `Gateway`, which says where each request goes.

## What is in the playground

The cluster has everything the module needs, except the two objects you write yourself:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm. `istio-base` and `istiod` run in `istio-system`. `istiod` is Istio's control plane: it turns Services and Istio objects into proxy configuration and sends it to every proxy.
- The **ingress gateway** in the namespace `istio-ingress`. Its Deployment and its Service are both called `istio-ingress`, and its pods carry the label **`istio=ingress`**. A `Gateway` must select that label.
- Mesh-wide **access logs**, so every proxy writes one line per request. Read the gateway's access log with `kubectl logs -n istio-ingress deploy/istio-ingress --tail=1`.
- The namespace **`starfleet`**, labelled for sidecar injection, with:
  - `bridge`, the web frontend (`/productpage`), and the backends `cargo`, `navcom` and **`scout` in three versions**, all on port `9080`. Each `scout` response names the pod that sent it (`"podname": "scout-v3-..."`).
  - The `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3`. A subset is a named group of a Service's pods, selected by labels.
  - **`probe`** v1 and v2 on port `8000`, an HTTP echo server that returns what it receives.
  - **`shuttle`**, a test client pod inside the mesh.
- **No `Gateway` and no `VirtualService`.** You write them.

You also need `istioctl` 1.30.5 on your own machine for the `istioctl` commands. Helm does not install it for you.

### Reaching the gateway

`kind` has no cloud load balancer, so nothing outside the cluster can reach the gateway on its own. `astrona run` keeps two port forwards running for you. A port forward sends connections from a local port on your machine to a Service inside the cluster. If one stops, astrona starts it again.

| Forward | Local | Goes to |
| --- | --- | --- |
| `ingress` | `http://127.0.0.1:8080` | the ingress gateway, port `80` |
| `bridge-ui` | `http://127.0.0.1:9080` | the `bridge` Service directly (no gateway) |

Check them with `astrona port-forward list`. You do not need to start a `kubectl port-forward` yourself.

## Helper

Paste this into each new terminal. It sends one request through the gateway for a path, with a `Host` header (`starfleet.example.com` unless you name another host), and prints only the HTTP status code:

```sh
gateway_status() { curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"; }
```

Use it like this: `gateway_status /productpage`, or `gateway_status /get probe.example.com`.

## Things to try

Each idea below is a small change to the files you saved while reading the module (`gateway-starfleet.yaml` and `virtualservice-bridge.yaml`). Edit your saved file, apply it with `kubectl apply -f`, and see what the gateway does.

- Check the gateway pod's labels before you write anything: `kubectl get pods -n istio-ingress -L istio`.
- Apply only the `Gateway` and see `404` with the `NR` response flag in the gateway's access log. Then add the `VirtualService` and see `/productpage` become `200`, while `/admin` stays `404`.
- Change the `Gateway` selector to `istio: ingressgateway`. Every request gets `000`, the port `80` listener disappears from `istioctl proxy-config listener deploy/istio-ingress -n istio-ingress`, and `istioctl analyze -n starfleet` reports `IST0101`.
- Remove `gateways:` from the `VirtualService`. The gateway answers `404 NR`, its route table shows only `blackhole:80`, and `istioctl analyze` reports nothing.
- Change the `VirtualService` host to `shop.example.com`. Both hosts get `404`, and `istioctl analyze` warns with `IST0132`.
- Set `hosts: ["*"]` on both objects. Now `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/productpage` gets `200` with no `Host` header at all.
- Add a first rule that sends `/reviews/` to the `scout` subset `v3`, and count which `scout` version answers `/reviews/0` through the gateway.
- Compare `istioctl proxy-config routes deploy/istio-ingress -n istio-ingress` before and after each change.

## Start over without a new cluster

This command deletes every `Gateway` and `VirtualService` in `starfleet`:

```sh
kubectl delete gateways.networking.istio.io,virtualservice --all -n starfleet
```

## Playground not working?

- `astrona list` shows the running environments. "already exists" means an old one is still there: run `astrona destroy ats-014-playground-060-01`, then run it again.
- The full log path is printed at the end of `astrona run` (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, run `kubectl config use-context kind-astro-ats-014-playground-060-01`.
- If `gateway_status` prints `000` even with a correct `Gateway`, check the port forward with `astrona port-forward list`.

## When you are done

```sh
astrona destroy ats-014-playground-060-01
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

The task below is written like an exam task. Try it on your own first, then open the solution. The solution was run and checked on a real cluster, and it uses the `gateway_status` helper.

### Task: expose the probe at a second host

> Expose the `probe` Service (port `8000`) in namespace `starfleet` at the host **probe.example.com** through the ingress gateway. Only the paths `/get` and `/headers` may be reachable. Use a `Gateway` named `probe-gateway` and a `VirtualService` named `probe`. The `bridge` page must stay reachable at `starfleet.example.com`.

<details><summary>Solution</summary>

The gateway needs a listener for the new host, and `probe` needs a `VirtualService` bound to it. Start with the `Gateway`. Save this as `gateway-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: probe-gateway
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
    - probe.example.com
```

Apply it:

```bash
kubectl apply -f gateway-probe.yaml
```

Then write the `VirtualService`. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe.example.com
  gateways:
  - probe-gateway
  http:
  - match:
    - uri:
        exact: /get
    - uri:
        exact: /headers
    route:
    - destination:
        host: probe
        port:
          number: 8000
```

Apply it:

```bash
kubectl apply -f virtualservice-probe.yaml
```

Then check the result with the two open paths, a closed path, and the `bridge` page:

```bash
gateway_status /get probe.example.com
gateway_status /headers probe.example.com
gateway_status /status/200 probe.example.com
gateway_status /productpage
```

```text
200
200
404
200
```

The two `match` entries are separate list items, so either path is enough (a logical OR). Every other path finds no route at the gateway and gets `404`. Both `Gateway` objects share the same port `80` listener, and the gateway's Envoy tells them apart by the `Host` header, so the `bridge` page keeps working.

</details>
