# Overview: Fault Injection With Delays And Aborts (Playground)

This is a **playground**, not a lab. It starts clean, installs Istio and the sample app, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What is in the playground

The playground is one small cluster with Istio and one namespace for the sample app:

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-050-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only. `istiod` is the Istio control plane; it sends configuration to every sidecar proxy.
- Access logs switched on for the whole mesh. An access log is the log where each sidecar proxy (Envoy) writes one line for every request. Its response flags `DI` (delay injected) and `FI` (fault injected) mark an injected fault.
- The **`starfleet`** namespace, with sidecar injection switched on:
  - `bridge`, `cargo`, `navcom`, and `scout` v1, v2 and v3, all on port `9080`. Only `scout` v2 and v3 call `navcom`, and the `scout` application copies the `end-user` header onto its request to `navcom`.
  - `probe` v1 and v2: an HTTP echo server behind one Service on port `8000`.
  - `shuttle`: the test client pod inside the mesh. Send every test request from here.
  - A `DestinationRule` for `scout` (subsets v1, v2, v3) and one for `navcom` (subset v1). A subset is a named group of pods of one Service, selected by a label.
- The `bridge` page at `http://127.0.0.1:9080/productpage`. Log in as `jason` to send requests with the header `end-user: jason`.
- **No `VirtualService` yet**, so no fault is injected. A `VirtualService` holds the routing rules for requests to a host, and a fault is a `fault` block on one of its rules.

You need `kubectl` and `istioctl` 1.30.5 on your own machine. `astrona check` tells you which tools are missing.

## Helper functions

Paste these into your terminal once per new terminal window:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_navcom_status() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
done | sort | uniq -c; }
```

`status_and_time` sends one request from `shuttle` and prints the status code and the total time. `count_navcom_status` sends 10 requests straight to `navcom` and counts the status codes.

## Start over without a new cluster

Delete every `VirtualService` you added. The playground starts with none, and the `DestinationRule` objects stay:

```sh
kubectl delete virtualservice --all -n starfleet
```

## When you are done

Remove the playground:

```sh
astrona destroy ats-014-playground-050-01
```

`astrona destroy` takes the name of the playground, not the folder path.

## Practice tasks

Each idea below is a small change to a `VirtualService` with a fault. Write the YAML in a file, apply it with `kubectl apply -f`, and watch what happens. The results shown were measured on a playground like this one.

- **Fail every request.** In a `navcom` `VirtualService` with an abort, set `httpStatus: 503` and `percentage.value: 100`. `status_and_time http://navcom:9080/ratings/0` answers at once: `503 0.003905s`.
- **Slow one request in ten.** In a `navcom` `VirtualService` with a delay, set `percentage.value: 10`. Out of 30 requests, about three are slow. One run gave 26 fast and 4 slow.
- **Fail only the requests from `scout`.** Replace a `headers` match with `sourceLabels: app: scout`. The request from `shuttle` straight to `navcom` still gets `200`, while the response for `jason` through `scout` shows `"Ratings service is currently unavailable"`.
- **Try to hide an abort behind retries.** Add `retries: attempts: 3, retryOn: 5xx` to the abort rule. About half the requests still fail, because a rule with a `fault` ignores its own retries.
- **Put a timeout on the fault rule.** Add `timeout: 0.5s` next to a 2-second delay. The request still takes two seconds: `200 2.104704s`.
- **Find the fault in the proxy configuration.** Run `istioctl proxy-config routes deploy/scout-v2 -n starfleet --name 9080 -o json` and search for `envoy.filters.http.fault`.

### Exam-style task: a delay for one calling workload

> Requests from `bridge` to `cargo` must be delayed by **3 seconds**. Requests from any other workload to `cargo` must stay fast.

Try the task on your own first, then open the solution. The solution was run and checked on a cluster like this one.

<details><summary>Solution</summary>

The fault goes on the `VirtualService` of `cargo`, the service that should look slow. A `sourceLabels` match selects `bridge` as the client, and a plain rule below it keeps every other request fast. Save this as `virtualservice-cargo-delay-from-bridge.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: cargo
  namespace: starfleet
spec:
  hosts:
  - cargo
  http:
  - match:
    - sourceLabels:
        app: bridge
    fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 3s
    route:
    - destination:
        host: cargo
  - route:
    - destination:
        host: cargo
```

Apply it:

```sh
kubectl apply -f virtualservice-cargo-delay-from-bridge.yaml
```

Then check the result. Send one request from `shuttle` straight to `cargo`, and two to `bridge`, which calls `cargo`:

```sh
status_and_time http://cargo:9080/details/0
status_and_time http://bridge:9080/productpage
status_and_time http://bridge:9080/productpage
```

You should see something like:

```text
200 0.008977s
200 3.108051s
200 3.030261s
```

The request from `shuttle` to `cargo` is fast. Every `bridge` page takes three seconds longer, because the sidecar proxy of `bridge` delays its request to `cargo`.

Delete the fault when you are done:

```sh
kubectl delete virtualservice cargo -n starfleet
status_and_time http://bridge:9080/productpage
```

```text
200 0.050802s
```

</details>
