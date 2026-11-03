# Question

Solve this question on: `terminal`

The `starfleet` namespace runs the `probe` in two versions behind one Service on port `8000`. A `VirtualService` named `probe` and a `DestinationRule` named `probe` (the subsets `v1` and `v2`) sit in `starfleet`, and they send all requests to subset `v2`. Three namespaces have sidecar injection and a `shuttle` client pod: `starfleet`, `dock` and `depot`.

The `shuttle` in `starfleet` is answered by `probe-v2` only. The `shuttle` in `dock` still gets answers from both versions when it calls `http://probe.starfleet.svc.cluster.local:8000/hostname`. The path `/hostname` returns the name of the pod that answered.

Change the objects in `starfleet` so that:

1.  The `VirtualService` `probe` is visible in its own namespace and in **`dock`**, and in no other namespace. Its `exportTo` list holds exactly those two namespaces.
2.  The `DestinationRule` `probe` has the **same `exportTo` list**. Without it, requests from `dock` fail even though the `VirtualService` is visible.
3.  Ten requests from the `shuttle` in `dock` to `http://probe.starfleet.svc.cluster.local:8000/hostname` are **all answered by `probe-v2`**.
4.  Ten requests from the `shuttle` in `starfleet` to `http://probe:8000/hostname` are still all answered by `probe-v2`.
5.  The `shuttle` in **`depot`** keeps the default behaviour: its requests are still spread over both versions. Do not export either object to `depot`, and do not add a `VirtualService` there.
6.  Leave the Deployments and the Service unchanged. Do not delete and recreate the two objects with another name.

The grader sends real requests from the three `shuttle` pods and reads the cluster list of the `dock` and `depot` proxies, so the objects have to be visible, not only configured.
