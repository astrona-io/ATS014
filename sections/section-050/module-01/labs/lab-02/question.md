# Question

Solve this question on: `terminal`

Astronaut, your mission: run two simulation drills on the planet `starfleet`, one slow ship and one ship that seems to be down.

The planet `starfleet` runs the Starfleet, the probe and the `shuttle` test client:

* `scout` — three ship classes, v1, v2 and v3, on port 9080. The flight plan sends signals with the header `end-user: jason` to v2 and everything else to v1. Only v2 and v3 call `navcom`.
* `navcom` — the navigation computer, on port 9080. Its docking instructions define subset `v1`.
* `probe` — an echo probe, v1 and v2 behind one Service on port 8000.
* `shuttle` — your test client, with `curl`.

There is no drill yet. Set them up so that:

1.  A `VirtualService` named `navcom` holds **every** signal to navcom for **2 seconds** with `fault.delay`, and routes it to subset `v1`. It has no abort.
2.  A `VirtualService` named `probe` fails **every** signal to the probe with **503** using `fault.abort`. It has no delay.
3.  A signal from the `shuttle` to `http://scout:9080/reviews/0` with `end-user: jason` still gets a **200**, about 2 seconds late, and scout v2's flight log marks its signal to navcom with the flag **`DI`**.
4.  A signal from the `shuttle` to `http://probe:8000/get` gets a **503** at once, the shuttle's flight log marks it with the flag **`FI`**, and the probe never receives it.
5.  Leave the `scout` flight plan, the Deployments and the Services unchanged.

The grader sends real signals from the `shuttle`, reads the flight logs of the shuttle, scout v2 and the probe, and checks both flight plans.
