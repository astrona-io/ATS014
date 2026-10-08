# Diagnosing The Gateway

Gateway problems show up as three results: a failed connection, a 404 or a 503. Most of the work in diagnosing them is telling them apart. This part covers that difference, the commands that settle it, and the module's pitfalls in one place.

## `000`, 404 and 503

| Result | Means | Look at |
| --- | --- | --- |
| **`000`** (empty reply, connection fails) | nothing listens on the port | does a `Gateway` exist, and does its `selector` match the gateway pod's labels |
| **404** (flag `NR`) | the request reached a listener but matched **no route** | `Host` header, `Gateway.hosts`, `VirtualService.hosts`, whether `gateways:` is set, the namespace in the `Gateway` reference, the path match list |
| **503** | it matched a route, but the backend could not be reached | `destination.host`, the port number, whether a named subset exists, whether the backend pods are ready |

Remember it as one sentence: **`000` is my gate, 404 is my flight plan, 503 is my backend.**

The difference is sharp because these are different stages inside the proxy. `000` means there is no listener at all. A 404 means Envoy found a listener but no route entry to use. A 503 means it found a route, picked a cluster, and that cluster had nothing healthy to send to. The endpoint check from section 010 applies unchanged.

> [!TIP]
> **Try it — produce each failure on purpose**
>
> Start from the working setup of part 2 (`gateway-bookinfo.yaml` and `virtualservice-bookinfo.yaml` applied), then:
>
> ```sh
> echo "--- wrong Host (no listener match) ---"
> gateway_status /productpage wrong.example.com
> echo "--- right Host, unmatched path (no route match) ---"
> gateway_status /nothing-here
> echo "--- route matches, destination does not exist ---"
> kubectl -n bookinfo patch virtualservice bookinfo --type merge \
>   -p '{"spec":{"http":[{"match":[{"uri":{"exact":"/productpage"}}],"route":[{"destination":{"host":"no-such-service","port":{"number":9080}}}]}]}}'
> sleep 2
> gateway_status /productpage
> ```
>
> Expect something like:
>
> ```text
> --- wrong Host (no listener match) ---
> 404
> --- right Host, unmatched path (no route match) ---
> 404
> --- route matches, destination does not exist ---
> 503
> ```
>
> Two 404s from different causes, then a 503 from a third. The status code alone cannot tell the first two apart. That is why the route dump in the next section matters. Restore the working route before moving on: `kubectl apply -f virtualservice-bookinfo.yaml`.

## Reading the gateway's own configuration

The gateway is an ordinary Envoy, so `istioctl proxy-config` works on it exactly as on a sidecar. Two commands settle almost everything:

**`listener`** answers "is anything accepting traffic on this port?" That covers a `Gateway` whose selector matched nothing, or a port you did not open. It is the check for `000`.

**`routes`** answers "did my `VirtualService` attach?" That covers the missing `gateways:` field, a host mismatch, and a wrong namespace in the `Gateway` reference.

> [!TIP]
> **Try it — the routes the gateway proxy actually holds**
>
> ```sh
> istioctl proxy-config routes deploy/istio-ingress -n istio-ingress | grep -i bookinfo
> istioctl analyze -n bookinfo
> ```
>
> What to look for (output not shown in full): a line with the host `bookinfo.example.com`, the path matches from your `VirtualService`, and the `VirtualService` that produced them, shown as `bookinfo.bookinfo` (name, then namespace). The analysis should report no issues.
>
> **If your host is missing from this list, the `VirtualService` never attached.** That is the single most useful check in the module. It tells "my routes are wrong" apart from "my routes are not there".

`istioctl analyze` helps with some gateway mistakes and not others:

| Mistake | Does `istioctl analyze` report it? |
| --- | --- |
| `Gateway` `selector` matches no pod | yes, `IST0101` |
| `VirtualService` host not on the `Gateway` | yes, `IST0132` |
| `VirtualService` with no `gateways:` field | **no**: a `VirtualService` attached to `mesh` is a valid object |
| `Gateway` reference to the wrong namespace | no |

## A short diagnostic order

When a gateway task does not work, this order finds the cause faster than re-reading YAML:

1. **`curl` with the right `Host`.** `000`, 404 or 503? That cuts the search space straight away.
2. For **`000`**: `kubectl get pods -n istio-ingress --show-labels` and compare with the `Gateway` `selector`. Then `istioctl proxy-config listener deploy/istio-ingress -n istio-ingress`.
3. For **404**: `istioctl proxy-config routes deploy/istio-ingress -n istio-ingress`. Is your host there at all?
   - Missing → the `gateways:` field, host overlap, or the namespace in the `Gateway` reference.
   - Present → the routes attached; check the path match list and the `Host` you sent.
4. For **503**: `istioctl proxy-config endpoints deploy/istio-ingress -n istio-ingress`. Does the destination cluster have endpoints?
5. **`istioctl analyze -n <namespace>`** catches selectors that match nothing, hosts missing from the `Gateway`, and missing subsets.
6. **The gateway's access log**, `kubectl logs -n istio-ingress deploy/istio-ingress --tail=1`. It is the gate's own flight log: the status code and a short flag such as `NR` (no route) for every request.

## Common pitfalls

> [!WARNING]
> **Leaving out `gateways:` in the `VirtualService`.** The routes attach to `mesh` and the gateway keeps returning `404 NR` however correct they look. The most common mistake in this section.
>
> **A `selector` copied from an `istioctl` install onto a Helm install.** `istio: ingressgateway` matches no pod here, so nothing listens and curl gets `000`. Check the pod labels.
>
> **Host mismatch between `Gateway` and `VirtualService`.** The two host lists must overlap. A `*` on one side does not rescue a typo on the other.
>
> **Referencing a `Gateway` in another namespace without `<namespace>/<name>`.** A silent 404: the short name is looked up in the `VirtualService`'s own namespace.
>
> **Reading a 503 as a routing problem.** A 503 means routing worked. Check the destination host, port, subset and endpoints.
>
> **Forgetting the `Host` header when testing.** Without it, curl sends the address you dialled, which matches no listener host. Every test in this module needs `-H "Host: ..."`, which the `gateway_status` helper adds for you.
>
> **Expecting an `EXTERNAL-IP` on a cluster with no load balancer.** On `kind` there is none. Use a port forward (the playground runs one for you) or a NodePort.
>
> **Declaring `protocol: TCP` for HTTP traffic.** You get a byte pipe with no host or path routing, which looks like routing that silently ignores your rules.
>
> **Trusting a clean `istioctl analyze`.** It does not know your `VirtualService` was meant to be attached to a gateway.

> *`000` is my gate, 404 is my flight plan, 503 is my backend — and the gateway's own route dump says which of the two 404s you have.*
