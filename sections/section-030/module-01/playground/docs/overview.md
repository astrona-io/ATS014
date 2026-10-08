# Overview: Load Balancer Policy And Session Affinity (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

This is a **playground**, not a lab: a training solar system where you can
practise without a mission score. The environment starts clean, installs
Istio and the test apps, and then waits. There is no task, no
`astrona submit`, and no pass/fail. Explore, break things, `astrona destroy`,
start over.

## What's in the box

- A single-node `kind` cluster called `astro-ats-014-playground-030-01`.
  `astrona run` points `kubectl` at it.
- **Istio 1.30.5**, installed with Helm: `istio-base` (the CRDs) and `istiod`
  (the control plane). There is no ingress or egress gateway, because this
  module does not need one.
- **Access logs switched on** for the whole mesh. Every sidecar writes one line
  per request in its black box flight log, including the address of the pod it
  picked.
- Namespace **`bookinfo`**, labelled `istio-injection=enabled`, containing:
  - `curl` — a client pod inside the mesh. You send every test request from it.
  - `httpbin` — a test server behind one Service on port `8000`. It runs
    **four pods**, a small squadron of spaceships: three of `httpbin-v1` and
    one of `httpbin-v2`. The path
    `/hostname` answers with the name of the pod that served the request.
- **No `DestinationRule`.** Istio's default load balancer (`LEAST_REQUEST`) is
  in force until you add one.

Every pod shows `2/2`: the app plus its `istio-proxy` sidecar. Check with
`kubectl get pods -n bookinfo`.

## The helper you need

Paste this into your terminal once per new terminal window. It sends 8
requests from the `curl` pod and counts which **pod** answered each one. You
can add extra `curl` options, such as a header. It also sets `$HOSTNAME_URL`,
the address the module calls.

```sh
count_pods() { for i in $(seq 1 8); do
  kubectl exec -n bookinfo deploy/curl -- curl -s "$@" | grep -o '"httpbin-[^"]*"'
done | sort | uniq -c; }
HOSTNAME_URL=http://httpbin:8000/hostname
```

## Ready-made files

The YAML the module uses is in [`../examples/`](../examples/). If you cloned
the repository, you can apply these files directly instead of writing them yourself:

| File | What it does |
| --- | --- |
| `01-destinationrule-httpbin-round-robin.yaml` | `simple: ROUND_ROBIN` for every httpbin pod |
| `02-destinationrule-httpbin-sticky-header.yaml` | sticky by the `x-user` header |
| `03-destinationrule-httpbin-sticky-cookie.yaml` | sticky by a cookie called `session`, created by the sidecar |
| `cases/c1-destinationrule-source-ip.yaml` | sticky by the caller's IP address |
| `cases/c2-destinationrule-query-param.yaml` | sticky by the `?user=` query parameter |
| `cases/c3-destinationrule-lb-per-subset.yaml` + `cases/c3-virtualservice-httpbin-v1.yaml` | `RANDOM` for the host, sticky by header for subset `v1` only, and all traffic sent to `v1` |

All three numbered files and the cases use the same name, `httpbin`. So each
`kubectl apply` **replaces** the previous DestinationRule.

## Things to try

- Run `count_pods $HOSTNAME_URL` with no DestinationRule, then with
  `ROUND_ROBIN`. With round robin, expect each of the four pods about twice.
- Make `x-user` sticky and compare `alice`, `bob` and `carol`. Two names landing
  on the same pod is a hash collision, not a bug.
- Send requests with **no** `x-user` header under the same policy, and watch the
  stickiness disappear.
- Apply the cookie rule and look for the `set-cookie` line:
  `kubectl exec -n bookinfo deploy/curl -- curl -s -i $HOSTNAME_URL | grep -i -E 'set-cookie|hostname'`.
- Apply case 1 (`useSourceIp`). Every request from the `curl` pod now lands on
  one pod, with no header or cookie at all.
- Apply case 2 and call `count_pods "$HOSTNAME_URL?user=alice"`. Keep the quotes:
  `?` is a special character in zsh.
- Apply both case 3 files. `alice` sticks to one v1 pod, and requests without
  the header spread over the three v1 pods only.
- Scale `httpbin-v1` from 3 to 4 pods during a sticky run and count how many of
  your test names move to another pod.
- Put `simple` and `consistentHash` in the same `trafficPolicy` and read the
  error.
- Compare `lbPolicy` across each change:
  `istioctl proxy-config cluster deploy/curl -n bookinfo --fqdn httpbin.bookinfo.svc.cluster.local -o json | grep lbPolicy`.
- Read the sidecar's own record of each choice:
  `kubectl logs -n bookinfo deploy/curl -c istio-proxy --tail=8`.

When you want an exam-style task, try [the practice task](practice.md).

## Start over without a new cluster

Remove this module's rules and you are back to the starting state:

```sh
kubectl delete dr httpbin -n bookinfo
kubectl delete vs httpbin -n bookinfo --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-030-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
