# Overview: TLS Settings In A DestinationRule (Playground)

This environment is a **playground**, not a lab. It starts a clean cluster, installs Istio and the test workloads, and then waits. There is no task, no `astrona submit`, and no pass or fail. You can explore, break things, run `astrona destroy`, and start over.

## What is in the environment

The playground is a single-node `kind` cluster called `astro-ats-014-playground-030-02`, and `astrona run` points `kubectl` at it. It runs **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod`. `istiod` is Istio's control plane; it sends configuration to every sidecar proxy. There is no gateway, because this module does not need one.

Access logs are switched on for every proxy. An access log is a line the proxy writes for each request, with the status code and the response flags.

Two namespaces hold the workloads:

- **`starfleet`**, with sidecar injection on. It runs `probe`, four HTTP echo pods behind one Service on port `8000` (three `probe-v1` pods and one `probe-v2` pod; the path `/hostname` returns the name of the pod that answered), and `shuttle`, the client pod you send test requests from. Every pod shows `2/2`: the application container plus its sidecar proxy (`istio-proxy`), the Envoy proxy that Istio adds to each pod.
- **`outpost`**, with sidecar injection **off**. It runs `drifter`, a client pod with no sidecar proxy, so its requests never pass through a proxy and it cannot use mTLS. It shows `1/1`.

There is **no `PeerAuthentication` and no `DestinationRule`**. Istio's automatic mTLS is in force, and the `probe` accepts both mTLS and plain connections. Check with `kubectl get pods -n starfleet` and `kubectl get pods -n outpost`.

## The helpers you need

The playground ships three helper scripts. Run each with `astrona res run <script> --`. Everything after `--` goes to `curl`.

- `count-pods.sh` sends 8 requests from the `shuttle` pod and counts which `probe` pod answered each one.
- `status-codes.sh` sends 8 requests from the `shuttle` pod and counts the HTTP status codes. The code `000` means curl got no HTTP response.
- `drifter-call.sh` sends one request from the `drifter` pod to the `probe` and prints the status code.

First set the address that you pass to the first two:

```sh
HOSTNAME_URL=http://probe:8000/hostname
```

## Things to try

Each idea is a small change to a `DestinationRule` or a `PeerAuthentication`. Write the YAML to a file, apply it with `kubectl apply -f`, and watch what changes.

- Run `astrona res run status-codes.sh -- $HOSTNAME_URL` and `astrona res run drifter-call.sh` with no policy at all. Both reach the probe.
- Print the `probe` cluster of the `shuttle` pod's proxy and find the TLS transport socket that automatic mTLS adds:
  `istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json | grep -E 'transportSocket|tlsMode'`.
- Apply a `DestinationRule` with `tls.mode: ISTIO_MUTUAL`, then with `tls.mode: DISABLE`, and compare the cluster dump each time.
- Apply a `PeerAuthentication` with `mtls.mode: STRICT` for the pods labelled `app: probe`, and run both `status-codes.sh` and `drifter-call.sh`.
- With `STRICT` in place, apply the `DISABLE` rule, and read the `shuttle` pod's access log: `kubectl logs deploy/shuttle -n starfleet -c istio-proxy --tail=5`.
- Define subsets `v1` and `v2`, route requests with the header `x-canary: true` to `v2`, and give only `v2` its own `tls` block with `DISABLE`.
- Set `DISABLE` at the top level and `ISTIO_MUTUAL` in `portLevelSettings` for port `8000`, and see which one wins.
- Set a subset `loadBalancer` and a host-level `loadBalancer.consistentHash` together, and read each cluster's `lbPolicy`.

## Start over without a new cluster

Remove this module's objects, and the probe is back to automatic mTLS and the permissive default:

```sh
kubectl delete destinationrule probe -n starfleet --ignore-not-found
kubectl delete virtualservice probe -n starfleet --ignore-not-found
kubectl delete peerauthentication probe -n starfleet --ignore-not-found
```

## When you are done

```sh
astrona destroy ats-014-playground-030-02
```

`astrona destroy` takes the environment name, not the folder path.

## Practice tasks

Try the task on your own first, then open the solution. The tasks were written without running the playground, so the solutions describe what you should see in words.

### Match a STRICT destination

Make the `probe` accept only mTLS connections, and give the `shuttle` pod a `DestinationRule` that matches. Prove that the `shuttle` pod still gets `200` and that the `drifter` pod does not.

<details><summary>Solution</summary>

A `PeerAuthentication` tells a workload's sidecar proxy which connections it accepts. Save this as `peerauthentication-probe.yaml`:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: probe
  namespace: starfleet
spec:
  selector:
    matchLabels:
      app: probe
  mtls:
    mode: STRICT
```

Apply it:

```sh
kubectl apply -f peerauthentication-probe.yaml
```

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
    tls:
      mode: ISTIO_MUTUAL
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send requests from both clients:

```sh
astrona res run status-codes.sh -- $HOSTNAME_URL
astrona res run drifter-call.sh
```

The `shuttle` pod gets eight `200` answers. The `drifter` pod does not get `200`; the code is usually `000`.

</details>

### Break one subset

With the same `PeerAuthentication` in place, change the `DestinationRule` so that requests with the header `x-canary: true` fail and all other requests still work.

<details><summary>Solution</summary>

Subsets need a route. Save this as `virtualservice-probe.yaml`:

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
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: probe
        subset: v2
  - route:
    - destination:
        host: probe
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Save this as `destinationrule-probe.yaml`, replacing the old file. Subset `v2` sets its own `tls` block, which replaces the host's:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
    trafficPolicy:
      tls:
        mode: DISABLE
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Then send requests with and without the header:

```sh
astrona res run status-codes.sh -- $HOSTNAME_URL
astrona res run status-codes.sh -- -H "x-canary: true" $HOSTNAME_URL
```

The requests without the header get `200`. The requests with the header get an error status, because subset `v2` sends plain text to a pod that accepts only mTLS.

</details>
