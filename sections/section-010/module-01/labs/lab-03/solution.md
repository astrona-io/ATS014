# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The Start section finds the fault. Items 1 and 2 fix it in the `DestinationRule`. Items 3 to 5 prove that traffic flows again, and items 6 and 7 prove that you changed nothing else.

---

## Start: Find The Fault

The task says that every request from `jason` to the `scout` Service fails with `503`, and that requests from everyone else still work. Confirm both from the `shuttle` pod. Then read the access log of its sidecar proxy. The proxy is the Envoy container that Istio adds to each pod, and its access log has one line per request. Wait a moment before you read it:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://scout:9080/reviews/0
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=2 | head -1
```

```text
503
200
[2026-10-20T20:09:54.962Z] "GET /reviews/0 HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 5 - "-" "curl/8.11.1" "c28b689e-878c-4ab9-ae68-d3089b55570b" "scout:9080" "-" outbound|9080|v2|scout.starfleet.svc.cluster.local - 10.96.69.48:9080 10.244.0.12:39040 - -
```

Three fields explain the failure. The response flag is `UH`, which means "no healthy upstream": the destination exists but holds no pod. The chosen endpoint is `"-"`, because there was no pod to choose. The destination is `outbound|9080|v2|scout…`, so the empty destination belongs to the `v2` subset. A subset is a named group of pods picked by labels.

Now ask Istio for its opinion. `istioctl analyze` checks the Istio objects of a namespace against each other and against the pods. Then ask the proxy for the endpoints of the `v2` cluster. A cluster is a named destination in Envoy, and an endpoint is the address of one pod:

```sh
istioctl analyze -n starfleet
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080|v2|scout.starfleet.svc.cluster.local"
```

```text
Error [IST0173] (DestinationRule starfleet/scout) The Subset v2 defined in the DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).
Error: Analyzers found issues when analyzing namespace: starfleet.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
```

The analyzer names the problem: the subset `v2` selects no pod. The `v2` cluster has no endpoint. Compare the label value that each subset asks for with the labels that the pods carry:

```sh
kubectl -n starfleet get destinationrule scout \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
kubectl -n starfleet get pods -l app=scout -L version
```

```text
v1=v1
v2=v20
v3=v3
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
scout-v1-85bf65868-7npwq    2/2     Running   0          47s   v1
scout-v2-866c98b568-56kxz   2/2     Running   0          47s   v2
scout-v3-668c6dfc68-h774b   2/2     Running   0          47s   v3
```

The subset `v2` asks for `version: v20`, but the pod carries `version: v2`. That one wrong value is the whole fault.

Before you fix it, save the state that items 6 and 7 must keep. Save the `VirtualService` and the identity of the Deployments and pods:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,APP:.metadata.labels.app,VERSION:.metadata.labels.version
```

```text
generation=1 uid=d7a32ced-800c-4cb1-bdbd-5fc72870862f
{"hosts":["scout"],"http":[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"scout","subset":"v2"}}]},{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]}
NAME        UID
bridge-v1   3ec802cf-5e3f-4d97-9362-be426bac58ec
cargo-v1    e78482d7-bce1-47e6-bd38-9d654c45d769
navcom-v1   424a8106-766d-4cde-9e0d-349261ee0442
scout-v1    d239d241-aa02-4668-80ac-1e86774fd902
scout-v2    89ecef8c-4313-4c1d-a8ac-38757561abbd
scout-v3    b9713c79-e765-4aaa-8779-d93e36125dab
shuttle     30fd4274-085b-4e10-82cb-23d632232a5c
NAME                         APP       VERSION
bridge-v1-bc4dc4fcc-4z6fg    bridge    v1
cargo-v1-6f787f8bd5-mw2hz    cargo     v1
navcom-v1-7467bbc689-6qtw2   navcom    v1
scout-v1-85bf65868-7npwq     scout     v1
scout-v2-866c98b568-56kxz    scout     v2
scout-v3-668c6dfc68-h774b    scout     v3
shuttle-7b5db664c-xlw2p      shuttle   <none>
```

---

## Items 1 And 2: Fix The Subsets In The `DestinationRule`

> **Task item 1:** The `DestinationRule` named `scout` in `starfleet` defines **exactly three subsets**: `v1`, `v2` and `v3`.
>
> **Task item 2:** Each subset selects pods by the `version` label, with the value equal to its own name (`v1` selects `version: v1`, and so on).

The two items need one change, so you fix them together. Replace the wrong value `v20` with `v2`. Save this as `destinationrule-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: scout
  namespace: starfleet
spec:
  host: scout
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
```

Apply it:

```sh
kubectl apply -f destinationrule-scout.yaml
```

```text
destinationrule.networking.istio.io/scout configured
```

Check item 1. Print the subset names:

```sh
kubectl -n starfleet get destinationrule scout -o jsonpath='{range .spec.subsets[*]}{.name}{" "}{end}{"\n"}'
```

```text
v1 v2 v3 
```

There are exactly three subsets. Check item 2. Print the label value of each subset:

```sh
kubectl -n starfleet get destinationrule scout \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
```

```text
v1=v1
v2=v2
v3=v3
```

Every subset selects the `version` value that equals its own name.

---

## Item 3: Every Subset Has A Healthy Endpoint

> **Task item 3:** Every subset has at least one healthy endpoint in the proxy of the `shuttle` pod.

`istiod`, the Istio control plane, sends the new configuration to every proxy. Wait a few seconds, then print the endpoints of the three subset clusters from the `shuttle` proxy:

```sh
for v in v1 v2 v3; do
  istioctl proxy-config endpoints deploy/shuttle -n starfleet \
    --cluster "outbound|9080|$v|scout.starfleet.svc.cluster.local" | tail -n +2
done
```

```text
10.244.0.8:9080     HEALTHY     OK                outbound|9080|v1|scout.starfleet.svc.cluster.local
10.244.0.10:9080     HEALTHY     OK                outbound|9080|v2|scout.starfleet.svc.cluster.local
10.244.0.9:9080     HEALTHY     OK                outbound|9080|v3|scout.starfleet.svc.cluster.local
```

Each cluster holds one `HEALTHY` endpoint. The `v2` cluster was empty before the fix. If it is still empty, wait a few seconds and run the command again.

---

## Item 4: `jason` Reaches `scout-v2`

> **Task item 4:** All 10 out of 10 requests sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.

Each response contains the name of the pod that sent it. Send 10 requests with the header and count the versions:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v2
```

All 10 requests reached `scout-v2`.

---

## Item 5: Everyone Else Reaches `scout-v1`

> **Task item 5:** All 10 out of 10 requests sent without that header are answered by `scout-v1`.

Send 10 requests without the header:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v1
```

All 10 requests reached `scout-v1`.

---

## Item 6: The `VirtualService` Is Unchanged

> **Task item 6:** The `VirtualService` named `scout` is **left unchanged**.

Run the two commands from the Start section again:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec}{"\n"}'
```

```text
generation=1 uid=d7a32ced-800c-4cb1-bdbd-5fc72870862f
{"hosts":["scout"],"http":[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"scout","subset":"v2"}}]},{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]}
```

The `generation` is still `1`, so nobody edited the object. The spec is the same as before.

---

## Item 7: The Workloads Are Unchanged

> **Task item 7:** Leave the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

Run the Deployment and pod commands from the Start section again, and let Istio check the namespace:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,APP:.metadata.labels.app,VERSION:.metadata.labels.version
istioctl analyze -n starfleet
```

```text
NAME        UID
bridge-v1   3ec802cf-5e3f-4d97-9362-be426bac58ec
cargo-v1    e78482d7-bce1-47e6-bd38-9d654c45d769
navcom-v1   424a8106-766d-4cde-9e0d-349261ee0442
scout-v1    d239d241-aa02-4668-80ac-1e86774fd902
scout-v2    89ecef8c-4313-4c1d-a8ac-38757561abbd
scout-v3    b9713c79-e765-4aaa-8779-d93e36125dab
shuttle     30fd4274-085b-4e10-82cb-23d632232a5c
NAME                         APP       VERSION
bridge-v1-bc4dc4fcc-4z6fg    bridge    v1
cargo-v1-6f787f8bd5-mw2hz    cargo     v1
navcom-v1-7467bbc689-6qtw2   navcom    v1
scout-v1-85bf65868-7npwq     scout     v1
scout-v2-866c98b568-56kxz    scout     v2
scout-v3-668c6dfc68-h774b    scout     v3
shuttle-7b5db664c-xlw2p      shuttle   <none>

✔ No validation issues found when analyzing namespace: starfleet.
```

The same seven Deployments exist with the same `UID` values, and the pods keep their labels. `istioctl analyze` now reports no issue.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-03
```

The grader sends real requests from the `shuttle` pod and reads the endpoints in its proxy.

---

## Mistakes That Fail The Grader

- **Changing the `VirtualService` (item 6).** Sending `jason` to `v1` or `v3` makes the `503` go away, but the `VirtualService` was correct. The grader checks that it is unchanged.
- **Relabelling the pods (items 2 and 7).** Changing the `scout-v2` pods to `version: v20` also removes the `503`, but the subset labels must match the pods as they are.
- **Deleting the `v3` subset or adding a fourth one (item 1).** The `DestinationRule` must define exactly `v1`, `v2` and `v3`.
- **Testing too fast (items 3 to 5).** `kubectl apply` returns before `istiod` has sent the new configuration to the proxy of `shuttle`. If `jason` still gets `503`, wait a few seconds and send the request again.
