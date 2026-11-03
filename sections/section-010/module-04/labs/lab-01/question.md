# Question

Solve this question on: `terminal`

The `starfleet` namespace runs the `probe`, an HTTP echo server, in two versions behind one Service on port `8000`:

* `probe-v1`: pods with the label `version: v1`
* `probe-v2`: pods with the label `version: v2`
* `probe`: one Service on port `8000` that selects on the `app` label only, so both versions receive traffic
* a `DestinationRule` named `probe` that defines the subsets `v1` and `v2`
* `shuttle`: a client pod with `curl`

Istio is installed and every pod in `starfleet` has a sidecar proxy. There is no `VirtualService`. The path `/hostname` returns the name of the pod that answered, and `/delay/N` waits N seconds.

The `probe` route table must be split across three `VirtualService` objects, all in the namespace `starfleet`:

1.  A delegate `VirtualService` named **`probe-hostname`** has **no `hosts` and no `gateways`**. It sends every request to subset **`v2`** on port `8000`.
2.  A delegate `VirtualService` named **`probe-delay`** has **no `hosts` and no `gateways`**. It matches requests whose URI starts with **`/delay/`**, sets a **timeout of `2s`**, and sends them to subset **`v1`** on port `8000`.
3.  A root `VirtualService` named **`probe`** for the host **`probe`** has **exactly three rules**, in this order: URI prefix **`/hostname`** delegates to `probe-hostname`; URI prefix **`/delay`** delegates to `probe-delay`; and a last rule with no match sends everything else to subset **`v1`** on port `8000`.
4.  The `shuttle` pod calls `http://probe:8000/hostname` and **every one of 10 requests** is answered by `probe-v2`.
5.  A request to `http://probe:8000/delay/1` returns `200`, and a request to `http://probe:8000/delay/5` returns **`504`** after about 2 seconds, not after 5.
6.  A request to `http://probe:8000/get` returns `200` every time, not `404`. The last rule of the root must catch it.
7.  Leave the Deployments, the Service and the `DestinationRule` unchanged.

The grader sends real requests from the `shuttle` pod and reads the proxy's route table, so the rules have to work, not only exist.
