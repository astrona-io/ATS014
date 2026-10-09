# Overview: How A Request Moves Through The Mesh (Playground)

Astronaut, this is your training solar system in the simulator: a **playground**, not a lab. It starts clean, installs Istio and the Starfleet, and then waits for you. There is no task, no `astrona submit`, and no pass or fail. Explore, break things, and start over whenever you like.

## What's in the box

- A single-node `kind` Kubernetes cluster, with `kubectl` pointed at it.
- **Istio 1.30.5** (`istio-base` and `istiod`, installed with Helm), with flight logs (access logs) switched on for the whole mesh. You need `istioctl` on your own machine.
- The planet **`starfleet`**, with injection switched on. Every ship shows `2/2`:
  - `bridge`, `cargo`, `scout` v1/v2/v3 and `navcom`: the Starfleet.
  - `shuttle`: your test client. Send every test signal from here.
  - `probe` v1/v2: the echo probe. Its Service listens on port `8000`, and its pods on `8080`.
- The planet **`outpost`**, with injection switched **off** on purpose. Its one ship, the `drifter`, shows `1/1`: the same client image as the shuttle, with no communications officer on board.
- The bridge page at `http://127.0.0.1:9080/productpage`.
- **No Istio traffic configuration at all.** This module is about what exists before you configure anything.

## Things to try

- Compare `kubectl -n starfleet get pods` with `kubectl -n outpost get pods`. One number in the `READY` column is the whole difference.
- Send a signal from the shuttle to cargo and read both flight logs: the sender's line says `outbound`, the receiver's says `inbound`.
- Send the same signal from the drifter, and see that only cargo's communications officer logs it.
- Run `istioctl proxy-status` and look for the drifter. It is not there, because it has no proxy.
- Follow a signal to the probe down all four layers with `istioctl proxy-config listener`, `routes`, `cluster` and `endpoints`, and notice the port change from `8000` to `8080`.
- Count how many destinations one proxy carries: `istioctl proxy-config cluster deploy/shuttle -n starfleet | wc -l`.
- Scale cargo to zero ships and read the `503 UH` in the shuttle's flight log. Then scale it back to one.

## When you're done

```sh
astrona destroy ats-014-playground-000-01
```

`astrona destroy` takes the playground's name, not the folder path.
