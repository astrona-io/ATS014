# Overview: Timeouts And Retries (Playground)

> Declared in [`../config.yaml`](../config.yaml) under `metadata.docs.guide`.

Welcome aboard, astronaut. This is a **playground**, your training solar system, not a lab. The environment starts clean, installs Istio and the Starfleet, and then waits. There is no task, no `astrona submit` and no pass or fail. Explore, break things, `astrona destroy`, start over.

## What's in the box

- A single-node `kind` Kubernetes cluster. `astrona run` points `kubectl` at it (context `kind-astro-ats-014-playground-040-01`).
- **Istio 1.30.5**, installed with Helm: `istio-base` and `istiod` only.
- Flight logs (access logs) switched on for the whole mesh. Every sidecar writes one line per signal, which is how you see timeouts and retries happen.
- The planet **`starfleet`**, labelled for sidecar injection, with:
  - **The Starfleet**: `bridge`, `cargo`, `navcom`, and `scout` v1, v2 and v3, all on port 9080. Only scout v2 and v3 call navcom.
  - **The probe** v1 and v2 behind one Service on port 8000. It fails on demand: `/status/503` always answers 503, `/status/200,503` picks one of the two at random, and `/delay/3` answers after 3 seconds.
  - **The shuttle**, your test client inside the mesh.
  - The scout's docking instructions (subsets v1, v2, v3) and a flight plan that sends `end-user: jason` to scout v2 and everyone else to v1.
- The bridge page at `http://127.0.0.1:9080/productpage`.
- **No timeout and no retry rule** yet. Only Istio's built-in default retry policy is active.

You need `kubectl` and `istioctl` 1.30.5 on your own machine. `astrona check` tells you which tools are missing.

## Helper functions

Paste these into your terminal once per new terminal window:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

`status_and_time` sends one signal from the shuttle and prints the status code and the total time. `count_received` counts how many signals the probe ships really received, from their flight logs. That is the only place you can see retries, because the sender only ever gets one answer.

## Things to try

Each idea below is a small change to the flight plans you made while reading the module. Edit your saved file, apply it with `kubectl apply -f`, and watch what happens.

- Time `/delay/3` with and without a 1-second `timeout` on the probe's flight plan, then find the `UT` flag in the shuttle's flight log.
- Make navcom slow with a delay drill and give scout a short abort window. Then read the `DI` line in scout v2's flight log and see that scout still waited the full delay.
- Put the delay and the timeout on the same rule, and watch the timeout never fire.
- Send `/status/503` before and after adding `retries`, and count the signals at the probe: 1, then 4.
- Turn the timeout down until it cuts off the retries, and check the arithmetic with `istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000 -o json`.
- Send a `POST` with retries on, then split the flight plan with a `method` match so only `GET` is re-sent.

When you want a real task, try the two exam-style drills in [practice.md](practice.md).

## Start over without a new cluster

Remove every flight plan and docking instruction you added, then put the playground's own scout flight plan back:

```sh
kubectl delete virtualservice probe navcom -n starfleet --ignore-not-found
kubectl delete destinationrule navcom -n starfleet --ignore-not-found
```

Apply it:

```sh
kubectl apply -f bootstrap/manifests/scout-jason-route.yaml
```

Run the last command from the `playground/` folder.

## When you're done

```sh
astrona destroy ats-014-playground-040-01
```

(`astrona destroy` takes the environment name, not the configuration path.)
