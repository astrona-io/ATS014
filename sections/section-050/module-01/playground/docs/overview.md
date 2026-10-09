# Overview: Fault Injection With Delays And Aborts (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a lab. The environment starts clean, installs Istio and the Starfleet, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-050-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only.
- Flight logs (access logs) switched on for the whole mesh. Every sidecar writes one line per signal, with the `DI` and `FI` flags that mark a drill.
- The planet **`starfleet`**, labelled for sidecar injection, with:
  - **The Starfleet**: `bridge`, `cargo`, `navcom`, and `scout` v1, v2 and v3, all on port 9080. Only scout v2 and v3 call navcom, and the scout passes the `end-user` label on to navcom.
  - **The probe** v1 and v2 behind one Service on port 8000.
  - **The shuttle**, your test client inside the mesh.
  - Docking instructions for the scout (subsets v1, v2, v3) and for navcom (subset v1).
- The bridge page at `http://127.0.0.1:9080/productpage`. Log in as `jason` to send jason's signals.
- **No flight plan** (`VirtualService`) yet, so no drill is running.

You need `kubectl` and `istioctl` 1.30.5 on your own machine. `astrona check` tells you which tools are missing.

## Helper functions

Paste these into your terminal once per new terminal window:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_navcom_status() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
done | sort | uniq -c; }
```

`status_and_time` sends one signal from the shuttle and prints the status code and the total time. `count_navcom_status` sends 10 signals straight to navcom and counts the status codes.

## Things to try

Each idea below is a small change to the flight plans you made while reading the module. Edit your saved file, apply it with `kubectl apply -f`, and watch what happens. The results shown were measured on a playground like this one.

- **Fail every signal.** In your navcom abort flight plan, set `httpStatus: 503` and `percentage.value: 100`. `status_and_time http://navcom:9080/ratings/0` answers at once: `503 0.003905s`.
- **Slow one signal in ten.** In your navcom delay flight plan, set `percentage.value: 10`. Out of 30 signals, about three are slow. One run gave 26 fast and 4 slow.
- **Fail only the scout's signals.** Swap the `headers` match for `sourceLabels: app: scout`. The shuttle's own signal to navcom still gets `200`, while jason's answer through the scout shows `"Ratings service is currently unavailable"`.
- **Hide an abort behind retries.** Add `retries: attempts: 3, retryOn: 5xx` to the abort rule. About half the signals still fail, because a drill rule ignores its own retries.
- **Time out on the drill rule.** Add `timeout: 0.5s` next to a 2-second delay. The signal still takes two seconds: `200 2.104704s`.
- **Find the drill in the proxy's orders.** Run `istioctl proxy-config routes deploy/scout-v2 -n starfleet --name 9080 -o json` and search for `envoy.filters.http.fault`.

When you want a real task, try the exam-style drill in [practice.md](practice.md).

## Start over without a new cluster

Remove every flight plan you added. The playground starts with none, and the docking instructions stay:

```sh
kubectl delete virtualservice --all -n starfleet
```

## When you're done

```sh
astrona destroy ats-014-playground-050-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
