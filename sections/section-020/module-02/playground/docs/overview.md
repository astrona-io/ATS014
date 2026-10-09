# Overview: Mirror Live Traffic To A Shadow Service (Playground)

This is a **playground**, not a lab. It starts a cluster, installs Istio and a test service, and then waits for you. There is no task, no `astrona submit` and no pass or fail. Try things, break things, run `astrona destroy` and start over.

## What is in the playground

The playground is one cluster with Istio and two workloads:

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-020-02`).
- **Istio 1.30.5**, installed with Helm: `istio-base` (the custom resource definitions) and `istiod`, the control plane that sends configuration to every sidecar proxy. There is no ingress or egress gateway. You need `istioctl` on your own machine for the `istioctl` commands.
- The namespace **`starfleet`**, labelled `istio-injection=enabled`, so every pod in it gets a sidecar proxy (Envoy). It runs:
  - **`probe`**, an HTTP echo server that returns what it receives, in two versions: `probe-v1` and `probe-v2`, both behind one Service on port `8000`. The path `/hostname` returns the name of the pod that handled the request.
  - **`shuttle`**, a test client pod inside the mesh. You send every test request from it.
- Access logs are switched on for the whole mesh. Each sidecar proxy writes one line per request it handles, and `kubectl logs <pod> -c istio-proxy` shows those lines.
- **No `DestinationRule` and no `VirtualService`.** You write both yourself.

Every pod shows `2/2`: the application container plus the `istio-proxy` sidecar container. The playground has no `bridge` or `scout` workloads. Mirroring is easiest to see on the `probe`, so the playground installs only that.

## The helpers

Paste this block once in each new terminal:

```sh
mark_start() { START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ); }
count_received()  { sleep 3; for v in v1 v2; do
  echo "probe-$v received: $(kubectl logs -n starfleet deploy/probe-$v -c probe --since-time=$START_TIME | grep -c 'GET /hostname')"
done; }
send_requests() { for i in $(seq 1 ${1:-5}); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c; }
```

The helpers do three jobs:

- `mark_start` saves the current time in `START_TIME`. Run it before a test.
- `count_received` counts the requests each version **received** since that time. It reads them from the application log of each version. Run it after a test.
- `send_requests` sends N requests from `shuttle` (5 if you give no number) and shows which version **sent the response**.

## Things to try

Each idea below is a small change to a `DestinationRule` or `VirtualService` you write yourself. Save the YAML to a file, apply it with `kubectl apply -f`, and watch what happens.

- Route all requests to v1 with no mirror. The responses and the received requests match.
- Add a mirror to v2. Clients still get responses only from v1, but v2 receives every request.
- Lower `mirrorPercentage` to 20, and count what v2 receives over 30 requests and over 100 requests.
- Mirror to a Deployment that returns `503` to every request. Clients still get `200`, while the broken pod returns `503` to every copy.
- Combine a 50/50 split with a mirror to v2, and work out how many requests v2 receives in total.
- Point the mirror at a subset that no `DestinationRule` defines. The client still gets normal responses, v2 receives nothing, and `istioctl analyze -n starfleet` reports `IST0101`.

## Start over without a new cluster

Delete every routing object, and the broken Deployment if you created one:

```sh
kubectl delete virtualservice,destinationrule --all -n starfleet
kubectl delete deployment probe-broken -n starfleet --ignore-not-found
```

## When you are done

```sh
astrona destroy ats-014-playground-020-02
```

`astrona destroy` takes the environment name, not the configuration path.

## Practice tasks

This is an exam-style task. Paste the helpers first; the solution uses them. Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Send all `probe` traffic to **v1** and mirror **50%** of it to **v2**.

<details><summary>Solution</summary>

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: probe, namespace: starfleet}
spec:
  host: probe
  subsets:
  - name: v1
    labels: {version: v1}
  - name: v2
    labels: {version: v2}
```

Apply it:

```bash
kubectl apply -f destinationrule-probe.yaml
```

Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: probe, namespace: starfleet}
spec:
  hosts: [probe]
  http:
  - route:
    - destination: {host: probe, subset: v1}
    mirror: {host: probe, subset: v2}
    mirrorPercentage: {value: 50.0}
```

Apply it:

```bash
kubectl apply -f virtualservice-probe.yaml
```

Then send 40 requests and count both sides:

```bash
mark_start; send_requests 40; count_received
```

You should see something like:

```text
  40 probe-v1
probe-v1 received: 40
probe-v2 received: 20
```

Every response came from v1, and v2 received copies of about half the requests. With only 20 requests the share moves around more: one run gave 13 copies.

</details>
