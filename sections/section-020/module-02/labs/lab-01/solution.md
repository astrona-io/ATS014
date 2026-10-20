# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. Item 1 creates the `DestinationRule`. Items 2, 3 and 4 build one `VirtualService` rule in three steps: first the route, then the mirror, then the percentage. Items 5 to 8 prove the result. The hard part is the proof: the proxy throws away the answers of the mirror, so the client output is the same whether the mirror works or not. You must look at the receiving side.

---

## Start: Read The Starting State

The task describes two versions of one application behind one Service, and no Istio routing. Check that this is true, and send 20 requests from the `tester` pod:

```sh
kubectl -n mirror-demo get pods -L app,version
kubectl -n mirror-demo get destinationrule,virtualservice
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE   APP                    VERSION
notification-service-v1-54dd46d4b6-z8dst   2/2     Running   0          7s    notification-service   v1
notification-service-v2-d79d6dcc4-h9vms    2/2     Running   0          7s    notification-service   v2
tester-69699fd775-2ppxr                    2/2     Running   0          7s    tester                 
No resources found in mirror-demo namespace.
  13 ["EMAIL","SMS"]
   7 ["EMAIL"]
```

Both versions send responses to clients now, because the Service selects pods on the `app` label only. At the end, clients must get only `["EMAIL"]`, while `v2` still receives requests.

Item 8 asks you to leave the workloads alone. Save their identity now:

```sh
kubectl -n mirror-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n mirror-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME                      REPLICAS   UID
notification-service-v1   1          abbcf21b-ebf6-483f-bd33-fc9f1b72942d
notification-service-v2   1          4e567dd9-56b6-45f7-b2e1-f80a5f503e75
tester                    1          9e8a68b1-f7de-429a-982d-2d5525f3eb00
{"app":"notification-service"}
```

---

## Item 1: Define The Subsets

> **Task item 1:** A `DestinationRule` named `notification-service` that defines two subsets, **`v1`** and **`v2`**, each selecting on the pods' **`version`** label.

A `DestinationRule` holds the policies for traffic to one host, and it defines subsets. A subset is a named group of pods, selected by labels. Both the route and the mirror refer to the subsets by name. Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: mirror-demo
spec:
  host: notification-service
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
kubectl apply -f destinationrule-notification-service.yaml
```

```text
destinationrule.networking.istio.io/notification-service created
```

Check item 1. Print the subsets. Then check that the `v2` cluster in the proxy of `tester` has an endpoint. The proxy is the Envoy container that Istio adds to each pod. A cluster is a named destination in Envoy, and an endpoint is the address of one pod:

```sh
kubectl -n mirror-demo get destinationrule notification-service \
  -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version}{"\n"}{end}'
istioctl proxy-config endpoints deploy/tester -n mirror-demo \
  --cluster "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local"
```

```text
v1=v1
v2=v2
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8084     HEALTHY     OK                outbound|80|v2|notification-service.mirror-demo.svc.cluster.local
```

The `v2` subset matters more than usual here. A mirror that points at a subset that does not exist, or at a subset whose labels select no pod, silently sends nothing, and the client cannot tell. The `v2` cluster has one healthy endpoint, so the mirror will have a pod to send copies to.

---

## Item 2: Route 100% Of The Requests To `v1`

> **Task item 2:** A `VirtualService` named `notification` for the host `notification-service`. Its first `http` rule routes **100% of client requests to subset `v1`**, with exactly one destination in `route`.

A `VirtualService` holds the routing rules for a host. Start with the route only. Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: mirror-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 100
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification created
```

Check item 2. Print the `http` list, and send 30 requests:

```sh
kubectl -n mirror-demo get virtualservice notification -o jsonpath='{.spec.http}{"\n"}'
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
[{"route":[{"destination":{"host":"notification-service","subset":"v1"},"weight":100}]}]
  30 ["EMAIL"]
```

The first rule has exactly one destination, `v1` with weight 100, and all 30 responses come from `v1`. This output is what a mirror would give too, so it proves only half of the task. `v2` receives nothing yet. Count the requests that reach the `v2` proxy, using the method from item 7:

```sh
sleep 5
BEFORE=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -X POST http://notification-service/notify; done'
sleep 5
AFTER=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
echo "copies this run: $((AFTER - BEFORE)) of 40"
```

```text
copies this run: 0 of 40
```

Without a mirror, `v2` receives 0 of 40 requests.

---

## Item 3: Mirror The Requests To `v2`

> **Task item 3:** The same rule **mirrors** the requests to subset **`v2`**.

Mirroring means that the proxy of the client sends a copy of each request to a second destination and throws away the response of the copy. Add `mirror` to the same rule. `mirror` is a sibling of `route`, not an entry inside the `route` list. It is a single destination with no `weight`. If you write `v2` as a second destination in `route`, you get a weighted split, and clients start to get responses from `v2`.

Edit `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: mirror-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 100
      mirror:
        host: notification-service
        subset: v2
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification configured
```

Check item 3. Print the `mirror` field, and let Istio check the objects:

```sh
kubectl -n mirror-demo get virtualservice notification -o jsonpath='{.spec.http[0].mirror}{"\n"}'
istioctl analyze -n mirror-demo
```

```text
{"host":"notification-service","subset":"v2"}

✔ No validation issues found when analyzing namespace: mirror-demo.
```

The rule mirrors to the `v2` subset, and the analyzer finds no problem. An undefined subset would show up here as `IST0101`.

---

## Item 4: Set `mirrorPercentage` To 100

> **Task item 4:** Set `mirrorPercentage` explicitly to **100**.

The default is 100%, so the mirror already copies every request. The task asks you to write it anyway. Add `mirrorPercentage` next to `mirror`, and save the final file:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: mirror-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 100
      mirror:
        host: notification-service
        subset: v2
      mirrorPercentage:
        value: 100.0
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

```text
virtualservice.networking.istio.io/notification configured
```

Check item 4:

```sh
kubectl -n mirror-demo get virtualservice notification -o jsonpath='{.spec.http[0].mirrorPercentage}{"\n"}'
```

```text
{"value":100}
```

The percentage is 100.

---

## Item 5: The Proxy Holds A Mirror Policy

> **Task item 5:** The proxy of the `tester` pod holds a mirror policy (`requestMirrorPolicies`) for the `v2` cluster.

The proxy of the client sends the copy, so the mirror policy lives in the route table of the `tester` proxy. Wait a few seconds for `istiod`, the Istio control plane, to send the change, then read it:

```sh
istioctl proxy-config routes deploy/tester -n mirror-demo -o json | grep -i -A9 requestMirrorPolicies
```

```text
                            "requestMirrorPolicies": [
                                {
                                    "cluster": "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local",
                                    "runtimeFraction": {
                                        "defaultValue": {
                                            "numerator": 1000000,
                                            "denominator": "MILLION"
                                        }
                                    },
                                    "traceSampled": false,
```

The cluster name contains `|v2|`, so the copies go to the `v2` subset. `runtimeFraction` is your `mirrorPercentage`. Envoy stores it as a fraction of one million, so `1000000` out of `MILLION` is 100%.

---

## Item 6: Clients Get Only `v1` Responses

> **Task item 6:** The grader sends 30 requests from `tester`. It fails if any response is the `v2` body, or if fewer than 28 responses are the `v1` body.

Send the same 30 requests as the grader:

```sh
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  30 ["EMAIL"]
```

All 30 responses are `["EMAIL"]`. Any `["EMAIL","SMS"]` here would mean that `v2` ended up in the `route` list instead of in `mirror`.

---

## Item 7: `v2` Received The Copies

> **Task item 7:** The grader sends 40 more requests and counts the `POST /notify` lines in the access log of the `v2` sidecar proxy. At least 30 copies must arrive, so a mirror that silently sends nothing fails, even though the client gets normal responses.

The proof is on the receiving side, in the access log of the `v2` sidecar proxy. That log has one line per request that passes through the proxy. The route sends nothing to `v2`, so every request in that log is a copy. The log already holds earlier copies, so count the lines before and after the test, and take the difference. Wait before each count, because the proxy writes a log line a moment after the request:

```sh
sleep 5
BEFORE=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -X POST http://notification-service/notify; done'
sleep 5
AFTER=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
echo "copies this run: $((AFTER - BEFORE)) of 40"
kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=1
```

```text
copies this run: 40 of 40
[2026-10-20T20:36:28.165Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 15 0 0 "10.244.0.10" "curl/8.23.0" "54494f4b-9d3f-9090-9dd2-397e9ff44f4b" "notification-service" "10.244.0.8:8084" inbound|8084|| 127.0.0.6:42043 10.244.0.8:8084 10.244.0.10:0 outbound_.80_.v2_.notification-service.mirror-demo.svc.cluster.local default
```

All 40 requests were copied to `v2`. The log line shows `200`, which is the answer of `v2`. The client never saw it. If `v2` returned errors, they would show up here while the client still got normal responses. If you skip the `sleep` before the first count, late lines from the earlier test are counted in the difference, and the number is too high.

---

## Item 8: The Workloads Are Unchanged

> **Task item 8:** Do not scale any Deployment (each stays at 1 replica), do not change the Service selector, and do not add a Deployment.

Run the two commands from the Start section again:

```sh
kubectl -n mirror-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n mirror-demo get svc notification-service -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME                      REPLICAS   UID
notification-service-v1   1          abbcf21b-ebf6-483f-bd33-fc9f1b72942d
notification-service-v2   1          4e567dd9-56b6-45f7-b2e1-f80a5f503e75
tester                    1          9e8a68b1-f7de-429a-982d-2d5525f3eb00
{"app":"notification-service"}
```

The output is the same as before. Every Deployment has one replica and the same `UID`, and the Service still selects on `app` only.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-01
```

The grader sends real requests and counts the copies in the access log of the `v2` proxy.

---

## Mistakes That Fail The Grader

- **`mirror` indented as an entry of `route` (item 3).** It is a sibling of `route`, and a single destination, not a list.
- **`v2` as a weighted destination in `route` (items 2 and 3).** That is traffic shifting, and clients start to get responses from the release candidate.
- **Mirroring to an undefined subset (items 1 and 3).** It fails silently. The client is fine and `v2` receives nothing. `istioctl analyze` names the problem.
- **Counting the access log of `v2` without a baseline (item 7).** The log holds copies from earlier runs. Take a count before the test.
- **Reading the application log instead of the access log of the proxy (item 7).** The grader counts the lines in the log of the `istio-proxy` container.
- **Expecting the response of the mirror to matter.** The proxy throws it away. Mirroring cannot compare responses.
- **Leaving out `mirrorPercentage` (item 4).** The default is 100%, so the mirror still works, but the task asks you to set it.
