# Overview: Route Requests Within The Mesh (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio and the sample application, and then waits. There is no task, no `astrona submit` and no pass or fail. You can explore, break things, run `astrona destroy` and start over.

## What is in the playground

The playground is one cluster with Istio and a small sample application. Nothing routes by version yet.

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no gateways). `istiod` is Istio's control plane: it sends configuration to every sidecar proxy.
- Mesh-wide **access logs**. Every sidecar proxy writes one line per request to the log of its `istio-proxy` container. You read it with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod in it gets a sidecar proxy. It holds:
  - The Istio Bookinfo sample with other names: `bridge` (the web frontend at `/productpage`), `cargo` (a backend for item details), `navcom` (a backend for star ratings) and **`scout` in three versions**. v1 shows no stars, v2 black stars and v3 red stars. Each `scout` response names the pod that sent it (`"podname": "scout-v2-..."`), so you can see the version.
  - **`shuttle`**, a test client pod in the mesh. You send every test request from it with `curl`.
  - **`probe`** v1 and v2 behind one Service on port `8000`. It is an HTTP echo server: it sends back what it receives (`/headers`, `/anything`), so you can see what the proxy changed.
- Every pod shows `2/2`: the application container plus its `istio-proxy` sidecar. The sidecar proxy (Envoy) is the container that all traffic in and out of the pod passes through.
- **No `DestinationRule` and no `VirtualService`.** Nothing is routed by version yet.
- The `bridge` page at `http://127.0.0.1:9080/productpage`. Refresh it to see the stars change. Log in as `jason` (any password works), and `bridge` adds the header `end-user: jason` to its requests to `scout`.
- The URL paths inside the images keep their original names: a request to `scout` goes to `http://scout:9080/reviews/0`.

## Helpers

Paste this once in each new terminal. `count_versions` sends 10 requests from `shuttle` to `scout` and counts which version answered. Any `curl` options you give it are passed on.

```sh
count_versions() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o 'scout-v[0-9]' || echo none
done | sort | uniq -c; }
SCOUT=http://scout:9080/reviews
```

Use it like this: `count_versions $SCOUT/0`, or `count_versions -H "end-user: jason" $SCOUT/0`.

## Start over without a new cluster

This command deletes every routing object in `starfleet`, so you are back at the starting state:

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
```

## Playground not working?

- `astrona list` shows running environments. "already exists" means an old one is still there: run `astrona destroy ats-014-playground-010-01`, then run it again.
- `astrona run` prints the full log path at the end (`~/.astrona/logs/`).
- If `kubectl` talks to another cluster, run `kubectl config use-context kind-astro-ats-014-playground-010-01`.
- A pod that shows `1/1` instead of `2/2` has no sidecar. Run `kubectl rollout restart deploy -n starfleet`.

## When you are done

```sh
astrona destroy ats-014-playground-010-01
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

Each idea below is a small change to a `VirtualService` or `DestinationRule` you write yourself. Edit your saved file (for example `virtualservice-scout.yaml`), apply it with `kubectl apply -f`, and watch what happens. Most of them need a `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3`, so create that first.

- Run `count_versions $SCOUT/0` with no rules at all. All three versions answer. Then apply only the `DestinationRule` with the three subsets and run it again. Nothing changes, because a `DestinationRule` alone routes no request.
- In your `VirtualService`, change the subset to `v4`, a name the `DestinationRule` does not define. Read the `503` and the `NC` flag in the access log, then run `istioctl analyze -n starfleet`.
- Set the subset back to `v1`, and instead change the label of the `v1` subset in the `DestinationRule` to `version: v9`. You get `503` again, but this time with `UH`.
- In a `VirtualService` with a `jason` rule and a catch-all, move the catch-all to the top. The `jason` rule is never used, and `istioctl analyze` warns with `IST0130`.
- Remove the catch-all completely and send a request without the `end-user: jason` header. You get a `404` with the `NR` flag, and `analyze` reports nothing.
- Write a `match` with a header and a path in one item, then split them into two items. One `-` is the only difference between AND and OR.
- Compare `istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080` before and after you apply a `VirtualService`.

The two tasks below are exam-style. Try each one on your own first, then open the solution. The solutions were run and checked on a real cluster, and they use the `count_versions` helper.

### Task 1: every request to one version

> In namespace `starfleet`, make sure **every** request to `scout` is served by
> version **v2** (black stars). Use a DestinationRule and a VirtualService both
> named `scout`. Verify on the product page.

<details><summary>Solution</summary>

Apply the `DestinationRule` (the subsets) first, then the `VirtualService` (the route). With that order, the route always has a subset to send requests to.

Save this as `destinationrule-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: scout, namespace: starfleet}
spec:
  host: scout
  subsets:
  - name: v1
    labels: {version: v1}
  - name: v2
    labels: {version: v2}
  - name: v3
    labels: {version: v3}
```

Apply it:

```bash
kubectl apply -f destinationrule-scout.yaml
```

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: scout, namespace: starfleet}
spec:
  hosts: [scout]
  http:
  - route:
    - destination: {host: scout, subset: v2}
```

Apply it:

```bash
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```bash

count_versions $SCOUT/0                               # 10 scout-v2
kubectl exec -n starfleet deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -c glyphicon-star
# a number > 0 = stars are shown (v1 shows none)
```

</details>

### Task 2: one header, one version

> Requests to `scout` with header `x-canary: true` must go to **v3**. All
> other requests go to **v1**.

<details><summary>Solution</summary>

This needs the `scout` `DestinationRule` from task 1 (subsets `v1`, `v2`, `v3`).

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: scout, namespace: starfleet}
spec:
  hosts: [scout]
  http:
  - match:
    - headers:
        x-canary: {exact: "true"}
    route:
    - destination: {host: scout, subset: v3}
  - route:
    - destination: {host: scout, subset: v1}
```

Apply it:

```bash
kubectl apply -f virtualservice-scout.yaml
```

Then check the result:

```bash

count_versions -H "x-canary: true" $SCOUT/0      #  10 scout-v3
count_versions $SCOUT/0                          #  10 scout-v1
```

`"true"` must be quoted: it is a string, not a YAML boolean.

</details>
