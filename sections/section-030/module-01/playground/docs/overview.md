# Overview: Load Balancer Policy And Session Affinity (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome, astronaut. This is your training solar system in the simulator: a **playground**, not a lab. It starts clean, installs Istio and the test ships, and then waits. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, `astrona destroy`, and start over.

## What's in the box

- A single-node `kind` cluster called `astro-ats-014-playground-030-01`. `astrona run` points `kubectl` at it.
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` (mission control). There is no gateway, because this module does not need one.
- **Flight logs (access logs) switched on** for every proxy. Each line names the pod address the proxy picked.
- The planet **`starfleet`**, with sidecar injection on:
  - `probe`: a squadron of four echo probes behind one Service on port `8000`: three `probe-v1` pods and one `probe-v2` pod. The path `/hostname` answers with the name of the pod that served the signal.
  - `shuttle`: your client. You send every test signal from here.
- **No `DestinationRule`.** Istio's default load balancer, `LEAST_REQUEST`, is in force until you add one.

Every pod shows `2/2`: the app plus its communications officer (the `istio-proxy` sidecar). Check with `kubectl get pods -n starfleet`.

## The helper you need

Paste this into each new terminal. It sends 8 signals from the shuttle to the probe and counts which pod answered each one. Any `curl` options you add are passed on:

```sh
count_pods() { for i in $(seq 1 8); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" | grep -o '"probe-[^"]*"'
done | sort | uniq -c; }
HOSTNAME_URL=http://probe:8000/hostname
```

## Things to try

Each idea is a small change to a `DestinationRule` for the probe. The module's parts show the full YAML for every step: save it to a file, apply it with `kubectl apply -f`, and watch what changes.

- Run `count_pods $HOSTNAME_URL` with no `DestinationRule`, then with `simple: ROUND_ROBIN`. With round robin, each of the four pods answers twice.
- Make the `x-user` header sticky and compare `alice`, `bob` and `carol`. Two names landing on one pod is a collision, not a bug.
- Under the same policy, send signals with **no** `x-user` header, and watch the stickiness disappear.
- Hash a cookie with `ttl`, and look for the `set-cookie` line:
  `kubectl exec -n starfleet deploy/shuttle -- curl -s -i $HOSTNAME_URL | grep -i -E 'set-cookie|hostname'`.
- Hash the source IP (`useSourceIp: true`). Every signal from the shuttle lands on one pod.
- Hash a query parameter and call `count_pods "$HOSTNAME_URL?user=alice"`. Keep the quotes: `?` is a wildcard in zsh.
- Give subset `v1` its own policy, route everything to `v1`, and compare each cluster's `lbPolicy`.
- Scale `probe-v1` from 3 to 4 pods during a sticky run, and count how many of your test names move.
- Put `simple` and `consistentHash` in the same `trafficPolicy`, and read the error.
- Read the policy the shuttle's proxy really uses:
  `istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json | grep lbPolicy`.

When you want an exam-style task, try [the practice task](practice.md).

## Start over without a new cluster

Remove this module's objects, and the probe is back to the default:

```sh
kubectl delete destinationrule probe -n starfleet
kubectl delete virtualservice probe -n starfleet --ignore-not-found
```

## When you're done

```sh
astrona destroy ats-014-playground-030-01
```

`astrona destroy` takes the environment name, not the folder path.
