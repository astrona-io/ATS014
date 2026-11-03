# Overview: Shift TCP Connections With Weights (Playground)

This is a **playground**, not a lab. It starts a cluster, installs Istio and a test service, and then waits for you. There is no task, no `astrona submit` and no pass or fail. Try things, break things, run `astrona destroy` and start over.

## What is in the playground

The playground is one cluster with Istio and two workloads:

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-020-03`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the custom resource definitions) and `istiod`, the control plane that sends configuration to every sidecar proxy. There is no ingress or egress gateway. You need `istioctl` on your own machine for the `istioctl` commands.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod in it gets a sidecar proxy (Envoy). It runs:
  - **`probe`**, an HTTP echo server in two versions, `probe-v1` and `probe-v2`, behind the Service `probe` on port `8000`. The port is named `http`. The path `/hostname` returns the name of the pod that handled the request.
  - **`shuttle`**, a test client pod inside the mesh. You send every test request from it.
- Access logs are switched on for the whole mesh. `kubectl logs <pod> -c istio-proxy` shows the lines of one sidecar proxy.
- **No `DestinationRule`, no `VirtualService` and no Service named `probe-tcp`.** You create all three yourself.

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar container.

## The helpers

Two scripts ship with the playground. Both send traffic from `shuttle` and count which version answered. They take the number of samples first (20 if you give none) and the target second (`probe-tcp:8000` if you give none). Put the arguments after `--`.

- `count-connections.sh` opens a new connection for every sample. Use it to measure a TCP split.
- `count-reused.sh` sends all samples over one connection. Use it to see that a connection stays on one pod.

```sh
astrona res run count-connections.sh -- 100
astrona res run count-reused.sh -- 20 probe:8000
```

## Things to try

Each idea below is a small change to objects you write yourself. Save the YAML to a file, apply it with `kubectl apply -f`, and measure.

- Create the Service `probe-tcp` with a port named `tcp`, and the subsets for it. Then write an 80/20 `tcp` route and count 100 connections.
- Send 20 requests over one connection with `count-reused.sh`, five times. Count how many different pods answered in each run.
- Change the weights to 3 and 1 and count 200 connections, to see what your proxy does with a total other than 100.
- Roll the weights 100/0, 90/10, 50/50 and 0/100, and back, with `kubectl patch`.
- Rename the port to `http`, and look for `weightedClusters` in the listener and for the `probe-tcp` host in the route table.
- Change the label of the `v2` subset to `version: canary`. Read the endpoints of the `v2` cluster and run `istioctl analyze -n starfleet`.
- Add a second `tcp` route that matches another port, and read the order in which the proxy applies them.

## Start over without a new cluster

Delete the Istio objects and the second Service:

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
kubectl delete service probe-tcp -n starfleet --ignore-not-found
```

## When you are done

```sh
astrona destroy ats-014-playground-020-03
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

This is an exam-style task. Try it on your own first, then open the solution. The playground was not run when this task was written, so check each result against what the commands show.

> Create a Service named `probe-tcp` for the `probe` pods, with a port that Istio treats as plain TCP. Then send 70% of the new connections to `probe` **v1** and 30% to **v2**, and prove the split with 100 fresh connections.

<details><summary>Solution</summary>

Save this as `service-probe-tcp.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata: {name: probe-tcp, namespace: starfleet, labels: {app: probe}}
spec:
  selector: {app: probe}
  ports:
  - {name: tcp, port: 8000, targetPort: 8080}
```

Apply it:

```bash
kubectl apply -f service-probe-tcp.yaml
```

Save this as `destinationrule-probe-tcp.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe-tcp, namespace: starfleet}
spec:
  host: probe-tcp
  subsets:
  - name: v1
    labels: {version: v1}
  - name: v2
    labels: {version: v2}
```

Apply it:

```bash
kubectl apply -f destinationrule-probe-tcp.yaml
```

Save this as `virtualservice-probe-tcp.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: probe-tcp, namespace: starfleet}
spec:
  hosts: [probe-tcp]
  tcp:
  - match:
    - port: 8000
    route:
    - destination: {host: probe-tcp, subset: v1, port: {number: 8000}}
      weight: 70
    - destination: {host: probe-tcp, subset: v2, port: {number: 8000}}
      weight: 30
```

Apply it:

```bash
kubectl apply -f virtualservice-probe-tcp.yaml
```

Then count 100 fresh connections:

```bash
astrona res run count-connections.sh -- 100
```

About 70 answers should come from `probe-v1` and about 30 from `probe-v2`. A count of `probe-v2` between 21 and 39 is within two standard deviations of 30, so it is a normal result. To see the weights in the proxy, run `istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -A12 weightedClusters`.

</details>
