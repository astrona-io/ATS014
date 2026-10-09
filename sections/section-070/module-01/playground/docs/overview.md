# Overview: Control External Access With ServiceEntry (Playground)

This is a **playground**, not a lab. It starts a fresh cluster, installs Istio, the `shuttle` client and the `probe` echo server, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, run `astrona destroy`, and start over.

## What is in the playground

The playground has one cluster, one namespace for your work, and nothing that limits outbound traffic yet:

- A single-node `kind` Kubernetes cluster. `kubectl` already points at it.
- **Istio 1.30.5**, installed with Helm (`istio-base` and `istiod` only, no gateways). `istiod` is Istio's control plane: it turns the cluster's Services and Istio objects into configuration and sends it to every sidecar proxy.
- The mesh at its default outbound traffic policy, **`ALLOW_ANY`**: the sidecar proxy lets requests to unknown hosts through. Switching to `REGISTRY_ONLY` is part of the module, not part of the setup.
- Mesh-wide **access logs**, so every sidecar proxy writes one line per request or connection. You read the `shuttle` pod's log with `kubectl logs -n starfleet deploy/shuttle -c istio-proxy`.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, with:
  - **`shuttle`**, the client pod inside the mesh. You send every test request from it with the `curl` command.
  - **`probe`** v1 and v2 behind one Service on port `8000`, an HTTP echo server inside the cluster. Compare a call to it with a call that leaves the cluster.
- **No `ServiceEntry` and no `Sidecar` resource.** The service registry, the list of hosts `istiod` knows about, holds only the Services in the cluster.

This playground calls `httpbin.org`, `de.wikipedia.org`, `en.wikipedia.org` and `www.google.com`. Without outbound internet access you see network failures, not decisions of the mesh. Run a plain `curl https://httpbin.org/get` on your own machine first.

## Helper

Paste this once in each new terminal. It sends one request from the `shuttle` pod and prints the status code, the time and the exit code of `curl`. `000` with exit code `35` or `56` means the connection was closed before any response:

```sh
call_external() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"; echo "  exit=$?"; }
```

To see what the `shuttle` pod's sidecar proxy did with the last request:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

## Things to try

Each idea below uses the YAML files you saved while reading the module:

- Call `https://httpbin.org/get` before anything else and find `PassthroughCluster` in the access log. The request is allowed, and Istio applies no rules to it.
- Apply the `REGISTRY_ONLY` `Sidecar`. Call `httpbin.org` again (`000`, `BlackHoleCluster`), then `http://probe:8000/get` inside the cluster (`200`). Only the undeclared call breaks.
- Add `httpbin.org` with a `ServiceEntry` on port `443` only. HTTPS works, and `http://httpbin.org/get` does not.
- Add port `80` as `HTTP` and a `VirtualService` with `timeout: 2s`, then call `http://httpbin.org/delay/4`: `504` after 2 seconds. Then change the port's protocol to `TCP` and call it again: the timeout no longer applies.
- With port `80` in the registry, call `http://www.google.com/`: `502` from the `block_all` route.
- Move the `ServiceEntry` to the namespace `default`. The host stays blocked, because the `starfleet` `Sidecar` never takes in configuration from `default`.
- Run `istioctl proxy-config cluster deploy/shuttle -n starfleet | grep httpbin.org` before and after each `ServiceEntry`, and watch the cluster appear.

## Start over without a new cluster

Delete the objects you created, and the namespace is back at its starting state:

```sh
kubectl delete serviceentry,virtualservice,destinationrule --all -n starfleet
kubectl delete serviceentry --all -n default
kubectl delete sidecar default -n starfleet
```

## When you are done

Remove the playground. `astrona destroy` takes the environment name, not the configuration path:

```sh
astrona destroy ats-014-playground-070-01
```

## Practice tasks

This is an exam-style task for this playground. Paste the `call_external` helper first, because the solution uses it. Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Pods in `starfleet` may reach only one outside host: **www.google.com** over HTTPS. Every other outside host must stay blocked, and the `ServiceEntry` must not open `www.google.com` for any other namespace.

<details><summary>Solution</summary>

First block unknown hosts in the namespace. Save this as `sidecar-registry-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: starfleet
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
```

Apply it:

```sh
kubectl apply -f sidecar-registry-only.yaml
```

Then add the one allowed host to the registry, limited to `starfleet` with `exportTo`. Save this as `serviceentry-google.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: google
  namespace: starfleet
spec:
  hosts:
  - www.google.com
  exportTo:
  - "."
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-google.yaml
```

Then check the result:

```sh
call_external https://www.google.com
call_external https://httpbin.org/get
```

You should see:

```text
200 0.122030s
  exit=0
000 0.014055s
command terminated with exit code 35
  exit=35
```

`www.google.com` answers through its `ServiceEntry`, and `httpbin.org` is refused because it is not in the registry.

</details>
