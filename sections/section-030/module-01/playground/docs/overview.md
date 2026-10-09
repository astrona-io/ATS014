# Overview: Load Balancer Policy And Session Affinity (Playground)

This environment is a **playground**, not a lab. It starts a clean cluster, installs Istio and the test workloads, and then waits. There is no task, no `astrona submit`, and no pass or fail. You can explore, break things, run `astrona destroy`, and start over.

## What is in the environment

The playground is a single-node `kind` cluster called `astro-ats-014-playground-030-01`, and `astrona run` points `kubectl` at it. It runs **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod`. `istiod` is Istio's control plane; it sends configuration to every sidecar proxy. There is no gateway, because this module does not need one.

Access logs are switched on for every proxy. An access log is a line the proxy writes for each request, and each line names the pod address the proxy picked. The workloads run in the **`starfleet`** namespace, with sidecar injection on:

- `probe`: four HTTP echo pods behind one Service on port `8000`: three `probe-v1` pods and one `probe-v2` pod. The path `/hostname` returns the name of the pod that served the request.
- `shuttle`: the client pod. You send every test request from here.

There is **no `DestinationRule`**, so Istio's default load balancer, `LEAST_REQUEST`, is in force until you add one. Every pod shows `2/2`: the application container plus its sidecar proxy (`istio-proxy`), the Envoy proxy that Istio adds to each pod. Check with `kubectl get pods -n starfleet`.

## The helper you need

Paste this into each new terminal. The `count_pods` function sends 8 requests from the `shuttle` pod to the `probe` Service and counts which pod answered each one. Any `curl` options you add are passed on:

```sh
count_pods() { for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o '"probe-[^"]*"'
done | sort | uniq -c; }
HOSTNAME_URL=http://probe:8000/hostname
```

## Things to try

Each idea is a small change to a `DestinationRule` for `probe`, the Istio object that holds policies for traffic to one host. Write the YAML to a file, apply it with `kubectl apply -f`, and watch what changes.

- Run `count_pods $HOSTNAME_URL` with no `DestinationRule`, then with `simple: ROUND_ROBIN`. With round robin, each of the four pods answers twice.
- Make the `x-user` header sticky with `consistentHash.httpHeaderName` and compare `alice`, `bob` and `carol`. Two names landing on one pod is a collision, not a bug.
- Under the same policy, send requests with **no** `x-user` header, and watch the stickiness disappear.
- Hash a cookie with `ttl`, and look for the `set-cookie` line:
  `kubectl exec -n starfleet deploy/shuttle -- curl -s -i $HOSTNAME_URL | grep -i -E 'set-cookie|hostname'`.
- Hash the source IP (`useSourceIp: true`). Every request from the `shuttle` pod lands on one pod.
- Hash a query parameter and call `count_pods "$HOSTNAME_URL?user=alice"`. Keep the quotes: `?` is a wildcard in zsh.
- Give subset `v1` its own policy, route everything to `v1` with a `VirtualService`, and compare each cluster's `lbPolicy`.
- Scale `probe-v1` from 3 to 4 pods during a sticky run, and count how many of your test names move.
- Put `simple` and `consistentHash` in the same `trafficPolicy`, and read the error.
- Read the policy the `shuttle` pod's proxy really uses:
  `istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json | grep lbPolicy`.

## Start over without a new cluster

Remove this module's objects, and the probe is back to the default:

```sh
kubectl delete destinationrule probe -n starfleet
kubectl delete virtualservice probe -n starfleet --ignore-not-found
```

## When you are done

```sh
astrona destroy ats-014-playground-030-01
```

`astrona destroy` takes the environment name, not the folder path.

## Practice tasks

Try the task on your own first, then open the solution. The solution was run and checked on the playground cluster, and it uses the `count_pods` helper.

### Sticky sessions by header

Make every request to the `probe` Service that carries the same `x-session-id` header reach the same pod.

<details><summary>Solution</summary>

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-session-id
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send 8 requests for each of two session ids:

```sh
count_pods -H "x-session-id: abc" $HOSTNAME_URL
count_pods -H "x-session-id: xyz" $HOSTNAME_URL
```

One run gave:

```text
   8 "probe-v1-7888d6c6d5-57cqj"
   8 "probe-v2-58767cc46-9srsh"
```

Each session id is pinned to one pod. The two ids may land on the same pod or on different ones; both are correct.

</details>
