# Practice: Route Requests Within The Mesh

Two exam-style missions for this playground, astronaut. Start the playground first, and
paste the helpers from [overview.md](./overview.md#helpers). The solutions use
them.

Try each task on your own first, then open the solution. The solutions were
run and checked on a real cluster.

## Task 1: every request to one version

> In namespace `starfleet`, make sure **every** request to `scout` is served by
> version **v2** (black stars). Use a DestinationRule and a VirtualService both
> named `scout`. Verify on the product page.

<details><summary>Solution</summary>

Apply the docking instructions (the subsets) first, then the flight plan (the
route). That order means the route always has somewhere to go.

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

## Task 2: one header, one version

> Requests to `scout` with header `x-canary: true` must go to **v3**. All
> other requests go to **v1**.

<details><summary>Solution</summary>

This needs the `scout` DestinationRule from task 1 (subsets `v1`, `v2`,
`v3`).

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
