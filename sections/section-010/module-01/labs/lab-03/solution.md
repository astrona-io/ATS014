# Solution Walkthrough

The `VirtualService` was correct all along. The `DestinationRule` pointed one subset at a label value that no pod carries, so the proxy of `shuttle` had no endpoint to send requests from `jason` to.

---

## Step 1: Confirm the failure

Send one request with the `end-user: jason` header, then read the last line of the access log of the `shuttle` proxy. The access log is one line per request in the log of the `istio-proxy` container:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T19:36:37.034Z] "GET /reviews/0 HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 0 - "-" "curl/8.11.1" "440e31c0-dd62-417c-baca-aacef60461a2" "scout:9080" "-" outbound|9080|v2|scout.starfleet.svc.cluster.local - 10.96.208.114:9080 10.244.0.11:42748 - -
```

Three fields in the log line explain the failure. The response flag is **`UH`**, "no healthy upstream": the cluster exists but has no endpoint. The chosen endpoint is `"-"`, because there was no pod to choose. And the cluster is `outbound|9080|v2|scout...`, so the empty cluster belongs to the `v2` subset.

## Step 2: Find the cause

Run `istioctl analyze`, which checks the Istio objects in a namespace against each other and against the pods:

```sh
istioctl analyze -n starfleet
```

```text
Error [IST0173] (DestinationRule starfleet/scout) The Subset v2 defined in the DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).
```

Confirm it in the proxy of `shuttle`. The `v2` cluster has no endpoints at all:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080|v2|scout.starfleet.svc.cluster.local"
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
```

Now compare the labels the subsets ask for with the labels the pods carry:

```sh
kubectl get destinationrule scout -n starfleet \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
kubectl get pods -n starfleet -l app=scout -L version
```

```text
v1=v1
v2=v20
v3=v3
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
scout-v1-85bf65868-96w4f    2/2     Running   0          56s   v1
scout-v2-866c98b568-5mzz8   2/2     Running   0          56s   v2
scout-v3-668c6dfc68-j2tm7   2/2     Running   0          56s   v3
```

The `v2` subset asks for `version: v20`, but the pod carries `version: v2`. That one wrong value is the whole fault.

## Step 3: Fix the DestinationRule

Save this as `destinationrule-scout.yaml`:

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

## Step 4: Prove it works

Then check the result. The `v2` cluster in the proxy of `shuttle` now holds an endpoint:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080|v2|scout.starfleet.svc.cluster.local"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.9:9080     HEALTHY     OK                outbound|9080|v2|scout.starfleet.svc.cluster.local
```

`istioctl analyze` is clean:

```sh
istioctl analyze -n starfleet
```

```text
✔ No validation issues found when analyzing namespace: starfleet.
```

And the requests reach the versions the `VirtualService` names. Send 10 requests with the `end-user: jason` header and 10 without it:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: jason" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c
```

```text
  10 scout-v2
  10 scout-v1
```

Now submit:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-03
```

---

## Common Mistakes

- **Changing the `VirtualService`.** Sending `jason` to `v1` or `v3` makes the `503` go away, but it fails the task. The `VirtualService` was correct, and the grader checks that it is unchanged.
- **Relabelling the pods.** Changing the `scout-v2` pods to `version: v20` also "fixes" it, but the subset's labels must match the pods as they are. The grader checks the pod labels.
- **Deleting the `v3` subset or adding a fourth one.** The `DestinationRule` must define exactly `v1`, `v2` and `v3`.
- **Testing too fast.** `kubectl apply` returns before `istiod` has sent the new configuration to the proxy of `shuttle`. If `jason` still gets `503`, wait a few seconds and send the request again.
