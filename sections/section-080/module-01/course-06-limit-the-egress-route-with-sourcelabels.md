# Limit The Egress Route With `sourceLabels`

With the two-stage `VirtualService` in place, every workload that calls `httpbin.org` goes through the egress gateway. Sometimes only some workloads should. This part limits hop 1 to the pods that carry one label, shows what that does and does not stop, and ends with what the egress gateway gives you and what it costs.

## `sourceLabels` selects the sending pod

Hop 1 is an ordinary rule in every sidecar proxy, so it can match on the usual fields. One of them is **`sourceLabels`**: the labels of the pod that **sends** the request. A rule with `sourceLabels: {egress-allowed: "true"}` only matches requests from pods that carry that label. Requests from every other pod skip the rule. With no other rule for `httpbin.org`, those requests go direct.

<!-- astrona:playground:renew -->

In your playground, the `shuttle` pod has no such label yet. The `-L` option adds a column for the label:

```sh
kubectl get pods -n starfleet -L egress-allowed
```

```text
NAME                      READY   STATUS    RESTARTS   AGE   EGRESS-ALLOWED
shuttle-7b5db664c-mbjjw   2/2     Running   0          5s
```

The `EGRESS-ALLOWED` column is empty.

### Only labelled pods use the egress gateway

The commands below need four objects in `starfleet` applied: the `ServiceEntry` `httpbin-org` for `httpbin.org` on port `443`, the `Gateway` `egress-gateway`, the `DestinationRule` `egress-gateway-for-httpbin-org` with the subset `httpbin-org`, and the two-stage `VirtualService` `httpbin-org-via-egress` in `virtualservice-httpbin-org-via-egress.yaml`.

Change hop 1 so it also matches on `sourceLabels`, and keep `gateways: [mesh]` in its `match`. Save this as `virtualservice-httpbin-org-allowed-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-org-via-egress
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  gateways:
  - mesh
  - egress-gateway
  tls:
  - match:
    - gateways:
      - mesh
      port: 443
      sniHosts:
      - httpbin.org
      sourceLabels:
        egress-allowed: "true"
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: httpbin-org
        port:
          number: 443
  - match:
    - gateways:
      - egress-gateway
      port: 443
      sniHosts:
      - httpbin.org
    route:
    - destination:
        host: httpbin.org
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin-org-allowed-only.yaml
```

Then send a request from `shuttle`, which has no label, and read its access log and its listener:

```sh
call_external
log_shuttle
istioctl proxy-config listener deploy/shuttle -n starfleet --port 443 | head -3
```

You should see (log line trimmed):

```text
200 0.485071s
  exit=0
"- - -" 0 - - - "-" 901 4875 596 - "-" "-" "-" "-" "98.89.203.252:443" outbound|443||httpbin.org ... httpbin.org -
ADDRESSES   PORT MATCH            DESTINATION
0.0.0.0     443  ALL              PassthroughCluster
0.0.0.0     443  SNI: httpbin.org Cluster: outbound|443||httpbin.org
```

The `shuttle` sidecar sends the request direct, and its listener for `httpbin.org` now points at the real host, not at the egress gateway. `istiod` only gives hop 1 to sidecars whose pod carries the label.

### Give the `shuttle` pod the label

The label belongs on the pod, so set it in the Deployment's pod template. This is one small change, so a short `kubectl patch` is enough. Kubernetes then replaces the pod:

```sh
kubectl patch deployment shuttle -n starfleet --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"egress-allowed":"true"}}}}}'
kubectl rollout status deployment/shuttle -n starfleet
```

```text
deployment.apps/shuttle patched
...
deployment "shuttle" successfully rolled out
```

Then send a request again and read both access logs:

```sh
call_external
log_shuttle
log_gate
```

You should see (log lines trimmed):

```text
200 0.513669s
  exit=0
"- - -" 0 - - - "-" 901 4875 631 - "-" "-" "-" "-" "10.244.0.6:443" outbound|443|httpbin-org|istio-egress.istio-egress.svc.cluster.local ... httpbin.org -
"- - -" 0 - - - "-" 901 4875 629 - "-" "-" "-" "-" "3.225.83.162:443" outbound|443||httpbin.org ... httpbin.org -
```

Now hop 1 goes to the egress gateway's pod, and the egress gateway opens the connection to the internet. It is the same `shuttle` workload and the same command; only the label changed.

Put the `shuttle` Deployment and the `VirtualService` back the way they were:

```sh
kubectl patch deployment shuttle -n starfleet --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/egress-allowed"}]'
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

## `tls` rules and `http` rules behave differently here

On Istio 1.30.5, the right way to combine `sourceLabels` with `gateways: [mesh]` depends on the kind of rule. These results were checked on a cluster like your playground:

| Hop 1 rule | With `gateways: [mesh]` | Without `gateways` in the `match` |
| --- | --- | --- |
| `tls` (HTTPS passed through) | works: only labelled pods use the egress gateway | **breaks**: the egress gateway also gets hop 1 and sends the request to itself; `shuttle` gets `000`, with `NC` in the egress gateway's log |
| `http` (plain HTTP) | **breaks**: `sourceLabels` is ignored, and every pod uses the egress gateway | works: only labelled pods use the egress gateway |

So for a `tls` hop 1, keep `gateways: [mesh]` next to `sourceLabels`, as you did above. For an `http` hop 1, match on the port and `sourceLabels` only. Whichever you write, prove it the same way: send a request from a pod **without** the label, and check that its access log ends at the internet, not at the egress gateway.

## A narrower route is not a block

Be precise about what `sourceLabels` gave you. It limits **the route, not the permission**. The `shuttle` pod without the label was not stopped: it went direct and got `200`, with no line in the egress gateway's access log. With `outboundTrafficPolicy` at `ALLOW_ANY`, every pod can still reach the internet without the egress gateway.

Turning the egress gateway into a real control takes three layers together:

| Layer | What does it | What it gives you |
| --- | --- | --- |
| The route | this `VirtualService` (optionally with `sourceLabels`) | which workloads go through the egress gateway |
| The permission | `outboundTrafficPolicy: REGISTRY_ONLY` | requests to hosts that are not in the service registry are blocked |
| The enforcement | an `AuthorizationPolicy` on the egress gateway, plus a Kubernetes `NetworkPolicy` | which workloads the egress gateway serves, and no direct path out of the cluster |

An **`AuthorizationPolicy`** allows or denies requests to a workload, here the egress gateway. A Kubernetes **`NetworkPolicy`** limits which pods may open connections to which addresses at the network level. With only the first layer, you have a convention. With all three, you have egress control.

## What the egress gateway gives, and what it costs

The exam can ask for the reasoning, not only the YAML, so know both sides.

What you gain:

- **One access log** for every request that leaves the cluster, with the address of the sending pod, instead of one line in whichever sidecar sent it.
- **One source address** that outside partners can allow, instead of the address of every node.
- **One place** to put policy, monitoring and rate limits on outbound traffic.
- **One place for client certificates**: the egress gateway can start the TLS connection itself, so only the egress gateway holds the keys.

What you pay:

- **An extra hop** on every outbound request, and the latency it adds.
- **A component on the critical path.** Every outbound request depends on the egress gateway. It needs capacity, monitoring and more than one replica, or one failed pod stops all outbound traffic.
- **More configuration per outside host**: four objects instead of one.

For a cluster with a few outside hosts and no audit or compliance need, letting each sidecar send direct is simpler and fine. The egress gateway is worth it when you need the single access log, the fixed source address, or one place for the certificates.

You now know how to send only labelled workloads through the egress gateway, why that is a route and not a permission, and when the egress gateway is worth its cost. The open question is which other layers your cluster needs before the egress gateway becomes a real control.

## Common pitfalls

> [!WARNING]
> - **Reading `sourceLabels` as a permission.** It limits the route. A pod without the label goes direct and still gets `200`.
> - **Copying the `sourceLabels` match between `tls` and `http` rules.** On Istio 1.30.5 they behave differently with `gateways: [mesh]`. Test with a pod that should **not** use the egress gateway.
> - **Labelling the Deployment instead of the pod.** `sourceLabels` reads the pod's labels. Set them in `spec.template.metadata.labels`.
> - **Believing the egress gateway is enforced.** Without `REGISTRY_ONLY`, an `AuthorizationPolicy` and a `NetworkPolicy`, any pod can still leave directly.
> - **A single egress gateway replica.** Every outbound request depends on it. Run more than one.

## Your mission: Route One Workload Through The Egress Gateway Lab

You can now build the two-stage route, prove the hop from the egress gateway's access log, and limit the route to the pods with one label. In the lab, you route a partner endpoint through the egress gateway for one client only, over plain HTTP, and show that another client still goes direct.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```

The task is on the next page. Solve it on your own first. The lab uses a different app and an older install, so the names differ from your playground: the egress gateway is `istio-egressgateway` in `istio-system`, with the label `istio: egressgateway`, and the clients run in the namespace `egwgw-demo`. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-01/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-080-01
astrona start ats-014-playground-080-01
```
