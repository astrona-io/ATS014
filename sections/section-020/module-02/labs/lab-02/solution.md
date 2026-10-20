# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The Start section finds the fault: the `VirtualService` is correct, but the `DestinationRule` gives the `v2` subset a label that no pod has. Items 1 and 2 are the fix and its first proof. Items 3 to 6 prove that the mirror works and that you changed nothing else. The client output cannot tell you whether the mirror works, so most checks look at the receiving side.

---

## Start: Show That `v2` Receives Nothing, And Find Why

A mirror makes two numbers differ: which version sent the response to the client, and which versions received the request. Count both with the same five requests. Take the time before you start, send the requests, wait, and count the `GET /hostname` lines in the application log of each version since that time:

```sh
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in $(seq 1 5); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
sleep 3
for v in v1 v2; do
  echo "probe-$v received: $(kubectl -n starfleet logs deploy/probe-$v -c probe --since-time=$START_TIME | grep -c 'GET /hostname')"
done
```

```text
   5 probe-v1
probe-v1 received: 5
probe-v2 received: 0
```

Every response comes from `v1`, as it should. But `v2` received nothing, although the `VirtualService` mirrors every request to it. Let `istioctl analyze` check the Istio objects of the namespace:

```sh
istioctl analyze -n starfleet
```

```text
Error [IST0173] (DestinationRule starfleet/probe) The Subset v2 defined in the DestinationRule does not select any pods. Which may lead to 503 UH (NoHealthyUpstream).
Error: Analyzers found issues when analyzing namespace: starfleet.
See https://istio.io/v1.30/docs/reference/config/analysis for more information about causes and resolutions.
```

The message `IST0173` points at the `DestinationRule`: the subset `v2` selects no pods. Confirm it in the proxy of `shuttle`. The proxy is the Envoy container that Istio adds to each pod, and the proxy of the client sends the copies. First check that the mirror policy exists, then check the endpoints of the mirror cluster. A cluster is a named destination in Envoy, and an endpoint is the address of one pod:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet -o json | grep -i -A3 requestMirrorPolicies
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
                            "requestMirrorPolicies": [
                                {
                                    "cluster": "outbound|8000|v2|probe.starfleet.svc.cluster.local",
                                    "runtimeFraction": {
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
```

The proxy is configured to send copies, but the destination has no endpoint. Compare the labels of the pods with the labels that each subset asks for:

```sh
kubectl -n starfleet get pods -l app=probe -L version
kubectl -n starfleet get destinationrule probe \
  -o jsonpath='{range .spec.subsets[*]}{.name}{" -> version="}{.labels.version}{"\n"}{end}'
```

```text
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
probe-v1-7888d6c6d5-hddqx   2/2     Running   0          20s   v1
probe-v2-58767cc46-p89h9    2/2     Running   0          20s   v2
v1 -> version=v1
v2 -> version=canary
```

The `probe-v2` pod carries `version=v2`, but the subset `v2` asks for `version=canary`. That is the fault.

Before you fix it, save the state that items 3 and 6 must keep:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
generation=1 uid=861b9d0e-3599-4c51-b016-14d45fa177ee
NAME       UID
probe-v1   b51a2a5f-68ab-4df8-9fd3-769c17a8c4dd
probe-v2   72e2d041-9261-408e-936c-b49b856af246
{"app":"probe"} 8000
```

---

## Item 1: Fix The Subsets

> **Task item 1:** The `DestinationRule` named `probe` defines the subsets **`v1`** and **`v2`**, each selecting on the pods' **`version`** label, so that each subset selects its own pods.

A `DestinationRule` holds the policies for traffic to one host, and it defines subsets. A subset is a named group of pods, selected by labels. The fix belongs in the `DestinationRule`. The pods and the `VirtualService` are correct. Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

Check item 1. Print the subsets, and let Istio check the objects again:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
istioctl analyze -n starfleet
```

```text
v1=v1
v2=v2

✔ No validation issues found when analyzing namespace: starfleet.
```

Each subset selects its own `version` label, and the error `IST0173` is gone.

---

## Item 2: The Mirror Cluster Has A Healthy Endpoint

> **Task item 2:** The mirror cluster `outbound|8000|v2|probe.starfleet.svc.cluster.local` has at least one healthy endpoint in the proxy of `shuttle`.

`istiod`, the Istio control plane, sends the change to the proxy. Wait a few seconds, then ask for the endpoints of the mirror cluster again:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe.starfleet.svc.cluster.local"
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:8080     HEALTHY     OK                outbound|8000|v2|probe.starfleet.svc.cluster.local
```

The cluster holds one `HEALTHY` endpoint. Before the fix, the list was empty. If it is still empty, wait a few seconds and run the command again.

---

## Item 3: One `VirtualService`, Unchanged

> **Task item 3:** There is still exactly one `VirtualService` for `probe`. Its first `http` rule routes every request to subset `v1` only, and mirrors to subset `v2` at **100%**.

You did not touch the `VirtualService`. Check that it still has the right shape, and that nobody edited it:

```sh
kubectl -n starfleet get virtualservice -o name
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http[0]}{"\n"}'
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
```

```text
virtualservice.networking.istio.io/probe
{"mirror":{"host":"probe","subset":"v2"},"mirrorPercentage":{"value":100},"route":[{"destination":{"host":"probe","subset":"v1"}}]}
generation=1 uid=861b9d0e-3599-4c51-b016-14d45fa177ee
```

There is one `VirtualService`. Its first rule routes to `v1` only, mirrors to `v2`, and the percentage is 100. The `generation` is still `1`, so nobody edited it.

---

## Item 4: Every Client Response Comes From `probe-v1`

> **Task item 4:** Every response that `shuttle` gets comes from `probe-v1`. The grader sends 30 requests to `http://probe:8000/hostname` and fails if any response comes from another version.

```sh
for i in $(seq 1 30); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
  30 probe-v1
```

All 30 responses come from `probe-v1`. The client got the same answers before the fix, so this check alone proves nothing about the mirror. Item 5 does.

---

## Item 5: `probe-v2` Receives The Copies

> **Task item 5:** `probe-v2` really receives the copies. The grader sends 20 more requests and counts the `GET /hostname` lines in the application log of `probe-v2`. At least 18 must arrive.

Wait a few seconds, so that late copies of the earlier requests do not count. Then repeat the count from the Start section with 20 requests:

```sh
sleep 5
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
sleep 4
for v in v1 v2; do
  echo "probe-$v received: $(kubectl -n starfleet logs deploy/probe-$v -c probe --since-time=$START_TIME | grep -c 'GET /hostname')"
done
```

```text
  20 probe-v1
probe-v1 received: 20
probe-v2 received: 20
```

All 20 responses still come from `probe-v1`, and `probe-v2` received a copy of every request. Before the fix, the same count gave `probe-v2 received: 0`.

---

## Item 6: Nothing Else Changed

> **Task item 6:** Leave the Deployments, the pod labels and the Service unchanged, and do not add or remove workloads.

Run the Deployment, pod and Service commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get pods -l app=probe -L version
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME       UID
probe-v1   b51a2a5f-68ab-4df8-9fd3-769c17a8c4dd
probe-v2   72e2d041-9261-408e-936c-b49b856af246
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
probe-v1-7888d6c6d5-hddqx   2/2     Running   0          35s   v1
probe-v2-58767cc46-p89h9    2/2     Running   0          35s   v2
{"app":"probe"} 8000
```

The Deployments have the same `UID` values, the pods keep their labels `v1` and `v2`, and the Service is the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-02
```

The grader counts the copies in the application log of `probe-v2`.

---

## Mistakes That Fail The Grader

- **Changing the `VirtualService` instead of the `DestinationRule` (items 1 and 3).** Routing to `v2`, or removing the mirror, breaks the task. The `VirtualService` was correct.
- **Changing the labels of the pods (items 1 and 6).** If you give the `probe-v2` pod the label `version: canary`, the subset selects it, but the grader requires the pods to stay unchanged.
- **Lowering `mirrorPercentage` (item 3).** The mirror must copy every request.
- **Checking only the client (items 4 and 5).** The client got correct responses before the fix, too. The proof is the endpoints of the mirror cluster and the copies that arrive at `probe-v2`.
- **Counting right after you send the requests (item 5).** The copies arrive a moment later, and a count taken too early is too low.
