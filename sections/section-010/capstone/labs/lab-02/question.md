# Question

Solve this question on: `terminal`

The `starfleet` namespace runs the `probe` in two versions behind one Service on port `8000`: `probe-v1` (pods with `version: v1`) and `probe-v2` (pods with `version: v2`). The path `/hostname` returns the name of the pod that answered, and `/delay/N` waits N seconds. Three namespaces have sidecar injection and a `shuttle` client pod: `starfleet`, `dock` and `depot`. There is no `DestinationRule` and no `VirtualService`.

The team wants a canary for the `probe`. Requests with the header `x-canary: true` go to `v2` and may take longer. Every other request goes to `v1` with a short timeout. Only `starfleet` and `dock` may see these rules. All objects go in the namespace `starfleet`.

1.  A `DestinationRule` named **`probe`** for the host `probe` defines the subsets **`v1`** and **`v2`** over the pod label `version`. Its `exportTo` list holds exactly the own namespace and **`dock`**.
2.  A root `VirtualService` named **`probe`** for the host `probe` has the **same `exportTo` list** and **exactly three rules**, in this order: URI prefix **`/hostname`** delegates to `probe-hostname`; URI prefix **`/delay`** delegates to `probe-delay`; and a last rule with no match sends everything else to subset `v1` on port `8000`.
3.  A delegate named **`probe-hostname`** has no `hosts` and no `gateways`. Its first rule matches the header **`x-canary`** with the exact value **`true`** and routes to subset **`v2`**. Its second rule has no match and routes to subset **`v1`**.
4.  A delegate named **`probe-delay`** has no `hosts` and no `gateways`. Its first rule matches the header `x-canary` with the exact value `true`, sets a **timeout of `6s`** and routes to `v2`. Its second rule has no match, sets a **timeout of `2s`** and routes to `v1`.
5.  From the `shuttle` in `starfleet` and from the `shuttle` in `dock`, ten requests to `/hostname` **with** the header are all answered by `probe-v2`, and ten requests **without** the header are all answered by `probe-v1`. The client in `dock` calls the host `probe.starfleet.svc.cluster.local`.
6.  From both clients, `/delay/4` **with** the header returns `200`, `/delay/4` **without** the header returns `504`, and `/delay/1` without the header returns `200`.
7.  The `shuttle` in **`depot`** is not affected by these objects. Its request to `/delay/4` without the header returns `200` (no timeout), and its requests to `/hostname` with the header are not all answered by `probe-v2`.
8.  Leave the Deployments and the Service unchanged, and create no Istio object in `dock` or `depot`.

The grader sends real requests from the three `shuttle` pods and reads the structure of every object, so each rule has to work, not only exist.
