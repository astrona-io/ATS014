# Practice: Route Requests Within The Mesh

Two exam-style missions for this playground, astronaut. Start the playground first, and
paste the helpers from [overview.md](./overview.md#helpers). The solutions use
them.

Try each task on your own first, then open the solution. The solutions were
run and checked on a real cluster.

## Task 1: every request to one version

> In namespace `bookinfo`, make sure **every** request to `reviews` is served by
> version **v2** (black stars). Use a DestinationRule and a VirtualService both
> named `reviews`. Verify on the product page.

<details><summary>Solution</summary>

Apply the docking instructions (the subsets) first, then the flight plan (the
route). That order means the route always has somewhere to go.

```bash
cat > destinationrule-reviews.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: reviews, namespace: bookinfo}
spec:
  host: reviews
  subsets:
  - name: v1
    labels: {version: v1}
  - name: v2
    labels: {version: v2}
  - name: v3
    labels: {version: v3}
EOF
kubectl apply -f destinationrule-reviews.yaml

cat > virtualservice-reviews.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: reviews, namespace: bookinfo}
spec:
  hosts: [reviews]
  http:
  - route:
    - destination: {host: reviews, subset: v2}
EOF
kubectl apply -f virtualservice-reviews.yaml

count_versions $REVIEWS/0                               # 10 reviews-v2
kubectl exec -n bookinfo deploy/curl -- curl -s http://productpage:9080/productpage | grep -c glyphicon-star
# a number > 0 = stars are shown (v1 shows none)
```

</details>

## Task 2: one header, one version

> Requests to `reviews` with header `x-canary: true` must go to **v3**. All
> other requests go to **v1**.

<details><summary>Solution</summary>

This needs the `reviews` DestinationRule from task 1 (subsets `v1`, `v2`,
`v3`).

```bash
cat > virtualservice-reviews.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: reviews, namespace: bookinfo}
spec:
  hosts: [reviews]
  http:
  - match:
    - headers:
        x-canary: {exact: "true"}
    route:
    - destination: {host: reviews, subset: v3}
  - route:
    - destination: {host: reviews, subset: v1}
EOF
kubectl apply -f virtualservice-reviews.yaml

count_versions -H "x-canary: true" $REVIEWS/0      #  10 reviews-v3
count_versions $REVIEWS/0                          #  10 reviews-v1
```

`"true"` must be quoted: it is a string, not a YAML boolean.

</details>
