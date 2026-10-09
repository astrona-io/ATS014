# Question

Solve this question on: `terminal`

A release candidate is ready, and the team wants it to handle real production requests before any user depends on it. No client may ever get a response from it.

The namespace `mirror-demo` runs two versions of one application behind a single Service:

* `notification-service-v1`: pods labelled `version: v1`, returns `["EMAIL"]`. This is the **stable** version.
* `notification-service-v2`: pods labelled `version: v2`, returns `["EMAIL","SMS"]`. This is the **release candidate**.
* `notification-service`: one Service on port `80` that selects on the `app` label only.
* `tester`: a client pod with `curl`. Send requests with `curl -X POST http://notification-service/notify`.

Istio is installed and every pod has a sidecar proxy. There is no `VirtualService` and no `DestinationRule`.

Create the following:

1.  A `DestinationRule` named `notification-service` that defines two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.
2.  A `VirtualService` named `notification` for the host `notification-service`. Its first `http` rule routes **100% of client requests to subset `v1`**, with exactly one destination in `route`.
3.  The same rule **mirrors** the requests to subset **`v2`**.
4.  Set `mirrorPercentage` explicitly to **100**.

The grader checks the result with real traffic:

5.  The proxy of the `tester` pod holds a mirror policy (`requestMirrorPolicies`) for the `v2` cluster.
6.  The grader sends 30 requests from `tester`. It fails if any response is the `v2` body, or if fewer than 28 responses are the `v1` body.
7.  The grader sends 40 more requests and counts the `POST /notify` lines in the access log of the `v2` sidecar proxy. At least 30 copies must arrive, so a mirror that silently sends nothing fails, even though the client gets normal responses.
8.  Do not scale any Deployment (each stays at 1 replica), do not change the Service selector, and do not add a Deployment.

Hint: the client's output cannot tell you whether the mirror works. Find the proof on the receiving side.
