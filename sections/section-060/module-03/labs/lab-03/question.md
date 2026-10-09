---
estimated_duration: 20m
---

# Question

Solve this question on: `terminal`

Astronaut, the spaceport gate on the planet `starfleet` is open, but its two flight plans are broken. Signals for the bridge page fail, and signals for the scout never find a route. Find out why, and fix both.

The planet `starfleet` holds the Starfleet:

* `bridge`: the flagship page, behind the `bridge` Service on port `9080`. Its page lives at `/productpage`.
* `scout` v1, v2 and v3: behind one `scout` Service on port `9080`. It answers at `/reviews/0`.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `cargo` and `navcom`: the rest of the fleet.

Istio 1.30.5 and the Gateway API objects are installed. Three objects exist:

* A `Gateway` named `starfleet-gateway`, with one HTTP listener on port 80 for the host name `starfleet.example.com`. Istio built its proxy, the Service `starfleet-gateway-istio`. **This gate is correct.**
* An `HTTPRoute` named `bridge`, meant to send the path prefix `/productpage` to the `bridge` Service.
* An `HTTPRoute` named `scout`, meant to send the path prefix `/reviews` to the `scout` Service.

Each `HTTPRoute` has one fault. Fix them so that:

1.  Both `HTTPRoute` objects, `bridge` and `scout` in `starfleet`, dock at the `Gateway` **`starfleet-gateway`** and report **`Accepted=True`** and **`ResolvedRefs=True`** on it.
2.  The gate's listener holds **2** attached routes.
3.  Both routes keep their host name **`starfleet.example.com`**, their `PathPrefix` paths (`/productpage` and `/reviews`) and their backend port **`9080`**. `bridge` sends to the **`bridge`** Service, `scout` to the **`scout`** Service.
4.  10 out of 10 signals sent from the `shuttle` to `http://starfleet-gateway-istio.starfleet/productpage` with the header **`Host: starfleet.example.com`** return **`200`**.
5.  10 out of 10 signals sent the same way to `/reviews/0` return **`200`**.
6.  The `Gateway` is **left unchanged**, and it stays the only `Gateway` in `starfleet`. Do not add, rename or remove Services or Deployments: fix the routes, not the fleet.

The grader reads the status of both routes and sends live signals through the gate from the `shuttle` pod, so the fix has to work, not merely exist.
