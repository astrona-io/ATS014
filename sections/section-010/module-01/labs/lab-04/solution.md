# Solution Walkthrough

The `VirtualService` has three faults on top of each other. Each fault hides the next one, so you fix them one at a time and watch the symptom change. The Start section finds all three. Items 1 and 2 fix the first fault. Item 5 fixes the second, and it comes before item 3 because item 3 only works after the order is right. Item 3 fixes the third fault. Items 4, 6 and 7 close the walkthrough.

---

## Start: See The Symptom And Find The Faults

The task says that every request lands on a random `scout` version. Send 10 requests with the header `end-user: jason`, and 10 without it, and count which version answered:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
   4 scout-v1
   4 scout-v2
   2 scout-v3
   4 scout-v1
   4 scout-v2
   2 scout-v3
```

Both loops give a mix of all three versions. The `VirtualService` routes nothing. Read the access log of the `shuttle` sidecar proxy. The proxy is the Envoy container that Istio adds to a pod. Wait a moment before you read the log:

```sh
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
[2026-10-20T20:13:03.408Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 440 7 7 "-" "curl/8.11.1" "45905918-3d2b-4142-b892-13b54a284d95" "scout:9080" "10.244.0.8:9080" outbound|9080||scout.starfleet.svc.cluster.local 10.244.0.12:44764 10.96.13.160:9080 10.244.0.12:36476 - default
```

The status is `200`, and the response flag is `-`. The cluster is `outbound|9080||scout…` and its subset field is empty. Nothing failed. The request used the plain `scout` cluster, as if no `VirtualService` existed.

Check the namespace `starfleet`, then look in every namespace:

```sh
istioctl analyze -n starfleet
kubectl get virtualservice,destinationrule -A
```

```text

✔ No validation issues found when analyzing namespace: starfleet.
NAMESPACE   NAME                                       GATEWAYS   HOSTS       AGE
default     virtualservice.networking.istio.io/scout              ["scout"]   7s

NAMESPACE   NAME                                        HOST    AGE
starfleet   destinationrule.networking.istio.io/scout   scout   7s
```

The `VirtualService` lives in `default`, not in `starfleet`. Istio fills in a short host name from the namespace of the object. In `default`, the host `scout` means `scout.default.svc.cluster.local`, a Service that does not exist. This is fault 1. Now let `istioctl analyze` check all namespaces:

```sh
istioctl analyze -A
```

```text
Error [IST0101] (VirtualService default/scout) Referenced host not found: "scout"
Error [IST0101] (VirtualService default/scout) Referenced host+subset in destinationrule not found: "scout+v1"
Error [IST0101] (VirtualService default/scout) Referenced host+subset in destinationrule not found: "scout+v4"
Warning [IST0130] (VirtualService default/scout) VirtualService rule #1 not used (route without matches defined before).
Info [IST0102] (Namespace default) The namespace is not enabled for Istio injection. Run 'kubectl label namespace default istio-injection=enabled' to enable it, or 'kubectl label namespace default istio-injection=disabled' to explicitly mark it as not needing injection.
Error: Analyzers found issues when analyzing all namespaces.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
```

The analyzer names all three faults:

- `Referenced host not found: "scout"` is the wrong namespace (fault 1).
- `IST0130 … rule #1 not used` means that a rule without `match` comes before another rule (fault 2).
- `scout+v4` is a subset that the `DestinationRule` does not define (fault 3).

The `IST0102` line says only that `default` has no sidecar injection. It does not matter for this task.

The task says that the `DestinationRule`, the Deployments and the Services must stay unchanged. Save their identity now. Items 6 and 7 compare against it:

```sh
kubectl -n starfleet get destinationrule scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,VERSION:.metadata.labels.version | grep scout
```

```text
generation=1 uid=28951d03-f599-4b07-8dbd-80c00b9d1e59
NAME        UID
bridge-v1   cc328944-7634-4b6b-b9ec-bcb233f23eab
cargo-v1    98f90679-7146-4a17-9892-a85ebc1a3c11
navcom-v1   3b1816c8-9a39-46c6-ac7f-ea30b07036ed
scout-v1    d163c268-5eea-4fcb-82a6-446f2477829a
scout-v2    bf3fafe9-e717-4505-8cd5-c75d6835995f
scout-v3    fd59c802-63c1-4e5c-9d60-75857583a9cb
shuttle     1f0eb0a1-b939-445f-a02c-ddd51c274c53
scout-v1-85bf65868-gzfjm     v1
scout-v2-866c98b568-j7n2g    v2
scout-v3-668c6dfc68-hxn8r    v3
```

---

## Items 1 And 2: Move The `VirtualService` To `starfleet`

> **Task item 1:** **Exactly one** `VirtualService` describes the host `scout.starfleet.svc.cluster.local`, and it routes the requests that `shuttle` sends.
>
> **Task item 2:** No `VirtualService` uses the short host `scout` in any namespace other than `starfleet`.

Both items have one fix: the `VirtualService` must live in `starfleet`. Delete the object in `default`. Then create the same object in `starfleet`, still with its other two faults, so that you can watch each symptom change.

Delete the old object:

```sh
kubectl delete virtualservice scout -n default
```

```text
virtualservice.networking.istio.io "scout" deleted from default namespace
```

Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v1
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v4
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
Warning: virtualService rule #1 not used (route without matches defined before)
virtualservice.networking.istio.io/scout created
```

Check items 1 and 2. List the `VirtualService` objects of all namespaces:

```sh
kubectl get virtualservice -A
```

```text
NAMESPACE   NAME    GATEWAYS   HOSTS       AGE
starfleet   scout              ["scout"]   8s
```

There is exactly one `VirtualService`, and it is in `starfleet`. No object with the short host `scout` is left in another namespace. The task also allows another fix: keep the object in `default` and write the full name `scout.starfleet.svc.cluster.local` everywhere. Do not do both. Two objects for the same host fail the grader.

Now send the two loops again:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v1
  10 scout-v1
```

The `VirtualService` routes requests now: everything goes to `v1`. But `jason` goes to `v1` too. `kubectl apply` already warned why. That is fault 2, and item 5 fixes it.

---

## Item 5: Put The `jason` Rule First, And The Catch-All Last

> **Task item 5:** The `VirtualService` has two rules: first the `jason` rule, then a catch-all rule with no `match`.

The proxy reads the rules from top to bottom and uses the first rule that matches. A rule without `match` matches every request. In the current file it comes first, so the proxy never reaches the `jason` rule. Swap the two rules. Edit `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v4
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

Check item 5. Print the rules in order, then send one request as `jason` and read the access log:

```sh
kubectl -n starfleet get virtualservice scout \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.subset}{"\n"}{end}'
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: jason" http://scout:9080/reviews/0
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
[{"headers":{"end-user":{"exact":"jason"}}}] -> v4
 -> v1
503
[2026-10-20T20:13:25.026Z] "GET /reviews/0 HTTP/1.1" 503 NC cluster_not_found - "-" 0 0 0 - "-" "curl/8.11.1" "4d9809c0-2f32-492f-94d8-05fc2abd10be" "scout:9080" "-" - - 10.96.13.160:9080 10.244.0.12:38938 - -
```

The order is right: the rule with the `match` comes first, and the rule without a `match` is last. Now the `jason` rule matches, and the request fails with `503` and the response flag `NC`, which means "no cluster". The rule asks for the subset `v4`, and the `DestinationRule` defines only `v1`, `v2` and `v3`. That is fault 3.

---

## Item 3: Route `jason` To `scout-v2`

> **Task item 3:** All 10 out of 10 requests sent with the header `end-user: jason` to `http://scout:9080/reviews/0` are answered by `scout-v2`.

The typo is in the `VirtualService`. The `DestinationRule` is correct, so do not change it. Change `subset: v4` to `subset: v2` in the `jason` rule:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v2
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

Check item 3. Send 10 requests with the header, and count the versions:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v2
```

All 10 requests reached `scout-v2`. If you still see `503`, wait a few seconds for `istiod`, the Istio control plane, to send the new rule to the proxy, and run the command again.

---

## Item 4: Everyone Else Reaches `scout-v1`

> **Task item 4:** All 10 out of 10 requests sent without that header are answered by `scout-v1`.

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

## Item 6: `istioctl analyze` Is Clean For The `VirtualService`

> **Task item 6:** `istioctl analyze -A` reports no `IST0101` and no `IST0130` for the `scout` `VirtualService`.

Run the analyzer on all namespaces. `-n starfleet` would not be enough, because it checks only one namespace:

```sh
istioctl analyze -A
```

```text
Info [IST0102] (Namespace default) The namespace is not enabled for Istio injection. Run 'kubectl label namespace default istio-injection=enabled' to enable it, or 'kubectl label namespace default istio-injection=disabled' to explicitly mark it as not needing injection.
```

No `IST0101` and no `IST0130` are left. Only the note about the namespace `default` remains, and it has nothing to do with the `VirtualService`.

---

## Item 7: Nothing Else Changed

> **Task item 7:** Leave the `DestinationRule`, the Deployments, their pod labels and the Services unchanged. Do not add or remove workloads.

Run the three commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule scout -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get pods -o custom-columns=NAME:.metadata.name,VERSION:.metadata.labels.version | grep scout
```

```text
generation=1 uid=28951d03-f599-4b07-8dbd-80c00b9d1e59
NAME        UID
bridge-v1   cc328944-7634-4b6b-b9ec-bcb233f23eab
cargo-v1    98f90679-7146-4a17-9892-a85ebc1a3c11
navcom-v1   3b1816c8-9a39-46c6-ac7f-ea30b07036ed
scout-v1    d163c268-5eea-4fcb-82a6-446f2477829a
scout-v2    bf3fafe9-e717-4505-8cd5-c75d6835995f
scout-v3    fd59c802-63c1-4e5c-9d60-75857583a9cb
shuttle     1f0eb0a1-b939-445f-a02c-ddd51c274c53
scout-v1-85bf65868-gzfjm     v1
scout-v2-866c98b568-j7n2g    v2
scout-v3-668c6dfc68-hxn8r    v3
```

The `DestinationRule` still has `generation=1`, so nobody edited it. The Deployments have the same `UID` values, and the pods keep their labels.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-04
```

The grader sends real requests from the `shuttle` pod.

---

## Mistakes That Fail The Grader

- **Fixing only what you can see (items 1, 3 and 5).** Each fault hides the next one. Moving the `VirtualService` alone leaves `jason` on `v1`. Swapping the rules alone leaves `jason` on `503 NC`.
- **Leaving the short host `scout` in `default` (items 1 and 2).** It describes `scout.default.svc.cluster.local`, so no rule ever matches.
- **Keeping the old `VirtualService` as well as the new one (item 1).** Two objects for the same host have no fixed order between them. The grader wants exactly one.
- **Fixing the subset by changing the `DestinationRule` (items 3 and 7).** The `DestinationRule` was correct. The typo is in the `VirtualService`.
- **Trusting `istioctl analyze -n starfleet` (item 6).** It checks one namespace only. Use `-A` when you do not know where an object lives.
