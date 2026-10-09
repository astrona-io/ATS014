---
estimated_duration: 15m
---

# Question

Solve this question on: `terminal`

The bridge has lost contact with its cargo service. In the `starfleet` namespace, the `bridge` page says "Error fetching product details", and every request to `cargo` fails with `503`. Nothing reports an error anywhere else.

The `starfleet` namespace runs these workloads:

* `cargo-v1`: a backend that returns item details, behind the `cargo` Service on port `9080`. Its pods carry the label `app: cargo`.
* `bridge-v1`: the web frontend. It calls `cargo` to fill in the product details on its page.
* `shuttle`: a client pod with `curl`. Send your test requests from here.
* `scout-v1`, `scout-v2`, `scout-v3` and `navcom-v1`: other backends of the app.

Istio 1.30.5 is installed, and every pod in `starfleet` has its sidecar proxy. There are no Istio objects. Every Deployment is running, and `istioctl analyze -n starfleet` reports no issues.

Find the fault and fix it so that:

1.  The `cargo` Service in `starfleet` selects the `cargo` pods again, on port `9080`.
2.  The `shuttle` sidecar proxy holds at least one healthy endpoint in the cluster `outbound|9080||cargo.starfleet.svc.cluster.local`. In Envoy, a cluster is a named destination, and its endpoints are the pod addresses behind it.
3.  All 10 out of 10 requests from `shuttle` to `http://cargo:9080/details/0` return `200`.
4.  The `bridge` page (`http://bridge:9080/productpage`, fetched from `shuttle`) shows the product details: it contains `ISBN-10`, and no longer says "Error fetching product details".
5.  The Deployments and their pod labels stay unchanged. Do not add or remove workloads. The fix belongs in the Service that selects the pods, not in the pods.

The grader reads the `cargo` Service, the configuration in the `shuttle` proxy, and live requests from `shuttle`, so the fix has to work, not only exist.
