# Match By Source Workload, Source Namespace And Port

Most routing rules look at the request: its path, its headers, its method. Sometimes the right answer depends on who sends the request, or on which port of the Service it uses. A test client should reach version 2 while production clients stay on version 1. A client in one namespace should get different routes from a client in another. This part covers the three `match` fields that answer these questions: `sourceLabels`, `sourceNamespace` and `port`.

The commands below need the `probe` `DestinationRule` with the subsets `v1` and `v2` exported to all namespaces (the default), and no `VirtualService` for `probe`. The playground has three client pods: `shuttle` and `patrol` in `starfleet`, and `shuttle` in `dock`. Remove the objects from the previous part first:

<!-- astrona:playground:renew -->

```sh
kubectl delete virtualservice probe -n starfleet --ignore-not-found
kubectl apply -f destinationrule-probe.yaml
```

If you no longer have the file, save this as `destinationrule-probe.yaml` first. It is the `DestinationRule` without a restricted `exportTo`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Then apply the file again with the `kubectl apply` command above, so that `exportTo` is back to its default.

## One VirtualService with three kinds of rule

The `match` of an `http` rule accepts three fields that say something about the sender or the destination:

- `sourceLabels`: labels that the **pod that sends the request** must have. The sidecar proxy of the sender compares them with the pod's labels.
- `sourceNamespace`: the namespace of the pod that sends the request.
- `port`: the port of the Service that the request is sent to, for example `8001` in `http://probe:8001`.

Save this as `virtualservice-probe.yaml`. The first rule sends requests from pods with the label `app: patrol` to subset `v2`. The second rule does the same for every pod in the namespace `dock`. The third rule sends requests to the Service port `8001` to subset `v2`. The last rule sends everything else to subset `v1`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - match:
    - sourceLabels:
        app: patrol
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - match:
    - sourceNamespace: dock
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8000
  - match:
    - port: 8001
    route:
    - destination:
        host: probe
        subset: v2
        port:
          number: 8001
  - route:
    - destination:
        host: probe
        subset: v1
        port:
          number: 8000
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then check the result from each client. Wait a few seconds after the apply. The first two commands use the same URL from two pods in `starfleet`. The third uses the client in `dock`. The fourth uses the Service port `8001`:

```sh
astrona res run count-versions.sh -- starfleet shuttle http://probe:8000/hostname
astrona res run count-versions.sh -- starfleet patrol http://probe:8000/hostname
astrona res run count-versions.sh -- dock shuttle http://probe.starfleet.svc.cluster.local:8000/hostname
astrona res run count-versions.sh -- starfleet shuttle http://probe:8001/hostname
```

The `shuttle` in `starfleet` gets `probe-v1` 10 times: none of the first three rules matches it. The `patrol` pod gets `probe-v2` 10 times, because of its label. The `shuttle` in `dock` gets `probe-v2` 10 times, because of its namespace. And the request to port `8001` gets `probe-v2` 10 times, even from the `shuttle` in `starfleet`.

## Each proxy gets its own rules

The same URL gave different answers from two pods in one namespace. The reason is where the rule is evaluated. `istiod` builds the route table for each sidecar proxy separately. A rule with `sourceLabels` or `sourceNamespace` goes only into the tables of the proxies that fit. Compare the two clients in `starfleet`:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
istioctl proxy-config routes deploy/patrol -n starfleet --name 8000
```

The table of `patrol` has a first row that sends all paths to subset `v2`, and the table of `shuttle` does not. The rule is not tested at request time against the pod's labels. It simply is not in the table of a proxy that does not fit.

A match entry can hold several conditions. Conditions in one entry must all be true (AND). A pod with the label `app: patrol` that uses port `8001` matches an entry that has both `sourceLabels` and `port`. Separate entries in the `match` list are alternatives (OR).

## What these matches cannot do

The three fields are routing conditions. They have limits that matter on the exam and in practice:

- **They need a sidecar proxy on the sender.** The sender's own proxy evaluates the rule. A pod without a sidecar proxy gets no routes from the mesh, so these matches never apply to it.
- **They are not an identity check.** The labels come from the pod, and whoever can create a pod chooses them. Likewise `sourceNamespace` is only the name of a namespace. Neither is a proof of who the sender is. To allow or deny a sender by its identity, use mutual TLS (mTLS) with an `AuthorizationPolicy`.
- **They match labels, not names.** There is no field for a pod name or a service account. Only pod labels work.
- **They need `mesh` in `gateways`.** If the `VirtualService` lists `gateways`, the list must include the reserved name `mesh` for `sourceLabels` and `sourceNamespace` to apply. These fields are meant for sidecar proxies, not for an ingress gateway.
- **They route, they do not deny.** A request that matches no rule gets the next rule or, with no catch-all, a `404`. To refuse a sender use an `AuthorizationPolicy`.
- **`port` is the destination port.** It is the Service port the client used, not the client's own port. It matters only when a Service has several ports, and the `destination` then needs its own `port` too.

You now know three ways to make a rule depend on the sender and on the destination port, and why each is a routing tool and not a security tool. The module has now shown how to split, limit and target a `VirtualService`.

## Common pitfalls

> [!WARNING]
> - **Matching on the Deployment's labels.** `sourceLabels` compares the labels of the pod (the pod template), not the labels of the Deployment.
> - **Forgetting `mesh` when `gateways` is set.** The rule is then not used for sidecar proxies, and no request matches it.
> - **Treating `sourceNamespace` or `sourceLabels` as security.** A pod can carry any label. Use mTLS and an `AuthorizationPolicy` for access control.
> - **Using `port` on a Service with one port.** It works, but it adds nothing. Use it when one host serves several ports that need different routes.
> - **Calling the host by its short name from another namespace.** A client in `dock` must use `probe.starfleet.svc.cluster.local`.
