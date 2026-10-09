# Overview: Route External Traffic Through An Egress Gateway (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, an egress gateway and the `shuttle` client, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio, an idle egress gateway and one client pod:

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5**, installed with Helm: `istio-base`, `istiod`, and an **egress gateway**. An egress gateway is an Envoy proxy that outbound traffic to outside hosts can be sent through, so the traffic leaves the mesh at one point. Here it is the Helm release `istio-egress` in the namespace `istio-egress`, its pods carry the label `istio: egress`, and its Service is type `ClusterIP` with ports `80` and `443`. It is running and carries no traffic.
- The mesh at its default `outboundTrafficPolicy`, **`ALLOW_ANY`**, so pods may send requests to any outside host.
- Access logs for the whole mesh. The `shuttle` sidecar proxy **and** the egress gateway each write one line per request into their access log.
- The **`starfleet`** namespace, with sidecar injection switched on. It runs **`shuttle`**, the test client pod in the mesh. Send every test request from it with `curl`.
- **No `ServiceEntry`, `Gateway`, `DestinationRule` or `VirtualService`.**

This playground calls `https://httpbin.org` and `https://www.google.com`, so it needs outbound internet access. Without it you see network failures, not mesh decisions. Run a plain `curl https://httpbin.org/get` on your own machine first.

## Helpers

Paste these once in each new terminal. `call_external` sends one request from `shuttle` (by default to `https://httpbin.org/get`). `log_shuttle` and `log_gate` print the newest line of the `shuttle` sidecar's access log and of the egress gateway's access log.

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"; echo "  exit=$?"; }
log_shuttle() { sleep 2; kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1; }
log_gate() { sleep 2; kubectl logs -n istio-egress deploy/istio-egress --tail=1; }
```

## Start over without a new cluster

This command deletes every Istio traffic object in `starfleet`:

```sh
kubectl delete virtualservice,destinationrule,serviceentry,gateways.networking.istio.io --all -n starfleet
```

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-080-01
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

Each idea below uses the YAML files you wrote while reading the module:

- Add `httpbin.org` with a `ServiceEntry` only, and call it. `log_shuttle` ends at an internet address, and the egress gateway logged nothing.
- Apply the `Gateway` and the `DestinationRule`, then run `istioctl proxy-config listener deploy/istio-egress -n istio-egress`. There is still no listener on `443`: it appears only with the `VirtualService`.
- Apply the two-stage `VirtualService`. Now hop 1 ends at the egress gateway's pod, and only hop 2 reaches the internet.
- Remove `mesh` from the top-level `gateways`. You get `200`, the request goes straight out, and `istioctl analyze` reports nothing.
- Remove hop 2, or put the egress gateway's own Service name in the `Gateway`'s `servers[].hosts`. The `shuttle` sidecar logs `UF,URX` with `Connection_refused`.
- Delete the `DestinationRule` while the `VirtualService` still names its subset. The `shuttle` sidecar logs `NC`.
- Add `sourceLabels` to hop 1, then add the label `egress-allowed: "true"` to the `shuttle` pod template, and watch the requests switch from direct to the egress gateway.

### Exam-style task: route `www.google.com` through the egress gateway

Route HTTPS traffic to **www.google.com** through the egress gateway, the same way as `httpbin.org`. Prove it in the egress gateway's access log. Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

<details><summary>Solution</summary>

The route needs four objects, applied in "make before break" order: the host in the service registry, the `Gateway`, the subset, and then the two-stage `VirtualService`.

Save this as `serviceentry-google.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata: {name: google, namespace: starfleet}
spec:
  hosts: [www.google.com]
  ports: [{number: 443, name: tls, protocol: TLS}]
  location: MESH_EXTERNAL
  resolution: DNS
```

Save this as `gateway-egress-google.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata: {name: egress-google, namespace: starfleet}
spec:
  selector: {istio: egress}
  servers:
  - port: {number: 443, name: tls, protocol: TLS}
    hosts: [www.google.com]
    tls: {mode: PASSTHROUGH}
```

Save this as `destinationrule-egress-gateway-for-google.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: egress-gateway-for-google, namespace: starfleet}
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets: [{name: google}]
```

Save this as `virtualservice-google-via-egress.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: google-via-egress, namespace: starfleet}
spec:
  hosts: [www.google.com]
  gateways: [mesh, egress-google]
  tls:
  - match: [{gateways: [mesh], port: 443, sniHosts: [www.google.com]}]
    route:
    - destination: {host: istio-egress.istio-egress.svc.cluster.local, subset: google, port: {number: 443}}
  - match: [{gateways: [egress-google], port: 443, sniHosts: [www.google.com]}]
    route:
    - destination: {host: www.google.com, port: {number: 443}}
```

Apply them, in this order:

```sh
kubectl apply -f serviceentry-google.yaml
kubectl apply -f gateway-egress-google.yaml
kubectl apply -f destinationrule-egress-gateway-for-google.yaml
kubectl apply -f virtualservice-google-via-egress.yaml
```

Then check the result:

```sh
call_external https://www.google.com
log_gate
```

You should see (log line trimmed):

```text
200 0.127331s
  exit=0
"- - -" 0 - - - "-" 861 92842 133 - "-" "-" "-" "-" "142.251.155.119:443" outbound|443||www.google.com ... www.google.com -
```

The egress gateway opened the connection to `www.google.com`, so hop 2 happened.

</details>
