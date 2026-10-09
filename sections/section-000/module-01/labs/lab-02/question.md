---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

Astronaut, the bridge has lost its supply ship. On the planet `starfleet`, the bridge page says "Error fetching product details", and every signal to `cargo` fails with `503`. Nothing reports an error anywhere else.

The planet `starfleet` holds the Starfleet:

* `cargo-v1`: the supply ship, behind a `cargo` Service on port `9080`. Its pods carry the label `app: cargo`.
* `bridge-v1`: the flagship page. It signals `cargo` to fill in the product details.
* `shuttle`: a client pod with `curl`. Send your test signals from here.
* `scout-v1`, `scout-v2`, `scout-v3` and `navcom-v1`: the rest of the fleet.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar. There are no Istio objects. Every Deployment is running, and `istioctl analyze -n starfleet` reports no issues.

Find the fault and fix it so that:

1.  The `cargo` Service in `starfleet` selects the `cargo` pods again, on port `9080`.
2.  The `shuttle`'s proxy holds at least one healthy endpoint in the cluster `outbound|9080||cargo.starfleet.svc.cluster.local`.
3.  All 10 out of 10 signals from the `shuttle` to `http://cargo:9080/details/0` answer `200`.
4.  The bridge page (`http://bridge:9080/productpage`, fetched from the `shuttle`) shows the product details: it contains `ISBN-10`, and no longer says "Error fetching product details".
5.  Leave the Deployments and their pod labels unchanged. Do not add or remove workloads. The fix belongs in the beacon that looks for the ships, not in the ships.

The grader reads the `cargo` Service, the shuttle's proxy and live signals from the `shuttle`, so the fix has to work, not merely exist.
